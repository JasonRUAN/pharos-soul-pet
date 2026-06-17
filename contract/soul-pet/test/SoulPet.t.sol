// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SoulPet.sol";

/// @title SoulPet 单元测试
/// @notice 覆盖领养、喂食冷却与饥饿衰减、陪玩/照料、冷落判定、
///         进化条件、社交串门、commit-reveal 繁育与关键 revert 路径。
contract SoulPetTest is Test {
    SoulPet internal pet;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    // 选取一个落在"非睡眠时段"（UTC 12:00）的基准时间，
    // 之后按整天数前进可保持同样的小时数，避免误触睡眠窗。
    uint256 internal constant START = 12 hours; // 43200，小时数为 12

    bytes32 internal constant TRAITS_A = bytes32(uint256(0xA1));
    bytes32 internal constant TRAITS_B = bytes32(uint256(0xB2));

    function setUp() public {
        pet = new SoulPet();
        vm.warp(START);
    }

    // ------------------------------------------------------------------
    // 工具：反复陪玩以快速积累亲密度（play 无冷却）
    // ------------------------------------------------------------------
    function _raiseAffinity(uint256 id, uint256 times) internal {
        for (uint256 i = 0; i < times; i++) {
            pet.play(id);
        }
    }

    // ------------------------------------------------------------------
    // 领养
    // ------------------------------------------------------------------
    function test_Adopt() public {
        vm.prank(alice);
        uint256 id = pet.adopt(TRAITS_A);

        assertEq(id, 1);
        assertEq(pet.ownerOf(id), alice);

        (address owner, uint16 hunger, uint16 mood, uint32 affinity, uint8 stage, bytes32 traits) = pet.stateOf(id);
        assertEq(owner, alice);
        assertEq(hunger, 0);
        assertEq(mood, 80);
        assertEq(affinity, 0);
        assertEq(stage, 0);
        assertEq(traits, TRAITS_A);
    }

    function test_AdoptIncrementsId() public {
        vm.prank(alice);
        uint256 a = pet.adopt(TRAITS_A);
        vm.prank(bob);
        uint256 b = pet.adopt(TRAITS_B);
        assertEq(a, 1);
        assertEq(b, 2);
    }

    // ------------------------------------------------------------------
    // 喂食：冷却 + 清空饥饿 + 提升心情/亲密度
    // ------------------------------------------------------------------
    function test_FeedResetsHungerAndCooldown() public {
        vm.startPrank(alice);
        uint256 id = pet.adopt(TRAITS_A);

        // 先让饥饿增长 8 小时（+40），20:00 仍在清醒时段
        vm.warp(START + 8 hours);
        (, uint16 hungerBefore,,,,) = pet.stateOf(id);
        assertEq(hungerBefore, 40);

        pet.feed(id);
        (, uint16 hungerAfter, uint16 moodAfter, uint32 affinityAfter,,) = pet.stateOf(id);
        assertEq(hungerAfter, 0); // 吃饱
        // 心情：80 初始 - 8h*3=24 衰减 = 56，再 +15 = 71
        assertEq(moodAfter, 71);
        assertEq(affinityAfter, 5);
        vm.stopPrank();
    }

    function test_FeedTooSoonReverts() public {
        vm.startPrank(alice);
        uint256 id = pet.adopt(TRAITS_A);
        vm.warp(START + 2 hours);
        pet.feed(id); // 第一次成功
        vm.expectRevert("Too soon to feed");
        pet.feed(id); // 立刻再喂 -> 冷却未到
        vm.stopPrank();
    }

    function test_FeedNotOwnerReverts() public {
        vm.prank(alice);
        uint256 id = pet.adopt(TRAITS_A);
        vm.warp(START + 2 hours);
        vm.prank(bob);
        vm.expectRevert("Not pet owner");
        pet.feed(id);
    }

    // ------------------------------------------------------------------
    // 饥饿衰减投影
    // ------------------------------------------------------------------
    function test_HungerProjectionCapsAt100() public {
        vm.prank(alice);
        uint256 id = pet.adopt(TRAITS_A);
        vm.warp(START + 100 hours); // 100h*5=500，封顶 100
        (, uint16 hunger,,,,) = pet.stateOf(id);
        assertEq(hunger, 100);
    }

    // ------------------------------------------------------------------
    // 陪玩 / 照料
    // ------------------------------------------------------------------
    function test_PlayBoostsMoodAffinityHunger() public {
        vm.startPrank(alice);
        uint256 id = pet.adopt(TRAITS_A);
        pet.play(id);
        (, uint16 hunger, uint16 mood, uint32 affinity,,) = pet.stateOf(id);
        assertEq(hunger, 5);
        assertEq(mood, 100); // 80+20
        assertEq(affinity, 8);
        vm.stopPrank();
    }

    function test_CareBoostsMood() public {
        vm.startPrank(alice);
        uint256 id = pet.adopt(TRAITS_A);
        // 先让心情下降：warp 10h -> 80-30=50
        vm.warp(START + 10 hours);
        pet.care(id);
        (,, uint16 mood, uint32 affinity,,) = pet.stateOf(id);
        assertEq(mood, 60); // 50+10
        assertEq(affinity, 3);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // 冷落判定 + statusText
    // ------------------------------------------------------------------
    function test_IsNeglectedAfterThreshold() public {
        vm.prank(alice);
        uint256 id = pet.adopt(TRAITS_A);
        assertFalse(pet.isNeglected(id));

        vm.warp(START + 2 days + 1);
        assertTrue(pet.isNeglected(id));

        string memory text = pet.statusText(id);
        assertEq(text, unicode"它好久没见到你了，有点失落，你是不是不要它了……");
    }

    function test_StatusTextHungry() public {
        vm.prank(alice);
        uint256 id = pet.adopt(TRAITS_A);
        vm.warp(START + 15 hours); // 饥饿 75 >=70
        assertEq(pet.statusText(id), unicode"它现在很饿，正眼巴巴地等你喂食。");
    }

    // ------------------------------------------------------------------
    // 进化
    // ------------------------------------------------------------------
    function test_EvolveSucceeds() public {
        vm.startPrank(alice);
        uint256 id = pet.adopt(TRAITS_A);

        // 先满足年龄：前进 1 天（保持 12:00 非睡眠）
        vm.warp(START + 1 days);
        // 再积累亲密度与心情（play 同一区块内无额外衰减）
        _raiseAffinity(id, 7); // affinity 56 >= 50，mood 拉满

        pet.evolve(id);
        (,,,, uint8 stage,) = pet.stateOf(id);
        assertEq(stage, 1);
        vm.stopPrank();
    }

    function test_EvolveTooYoungReverts() public {
        vm.startPrank(alice);
        uint256 id = pet.adopt(TRAITS_A);
        _raiseAffinity(id, 7); // 亲密度够，但年龄不够
        vm.expectRevert("Too young to evolve");
        pet.evolve(id);
        vm.stopPrank();
    }

    function test_EvolveAffinityTooLowReverts() public {
        vm.startPrank(alice);
        uint256 id = pet.adopt(TRAITS_A);
        vm.warp(START + 1 days);
        _raiseAffinity(id, 3); // 仅 24 亲密度 < 50
        vm.expectRevert("Affinity too low to evolve");
        pet.evolve(id);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // 记忆锚点
    // ------------------------------------------------------------------
    function test_CommitMemory() public {
        vm.startPrank(alice);
        uint256 id = pet.adopt(TRAITS_A);
        bytes32 root = keccak256("memory-001");
        pet.commitMemory(id, root);
        // pets(id) 公共 getter 按结构体字段顺序返回，memoryRoot 为最后一个
        (,,,,,,,,, bytes32 storedRoot) = pet.pets(id);
        assertEq(storedRoot, root);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // 社交：串门
    // ------------------------------------------------------------------
    function test_VisitBoostsBothMoods() public {
        vm.prank(alice);
        uint256 idA = pet.adopt(TRAITS_A);
        vm.prank(bob);
        uint256 idB = pet.adopt(TRAITS_B);

        // 先让双方心情下降，便于观察提升（20:00 仍清醒）
        vm.warp(START + 8 hours); // 80-24=56

        vm.prank(alice);
        pet.visit(idA, idB);

        (,, uint16 moodA,,,) = pet.stateOf(idA);
        (,, uint16 moodB,,,) = pet.stateOf(idB);
        assertEq(moodA, 68); // 56+12
        assertEq(moodB, 68);
    }

    function test_VisitSelfReverts() public {
        vm.startPrank(alice);
        uint256 id = pet.adopt(TRAITS_A);
        vm.expectRevert("Cannot visit self");
        pet.visit(id, id);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // 繁育：commit-reveal + 区块熵
    // ------------------------------------------------------------------
    function test_BreedFullFlow() public {
        vm.startPrank(alice);
        uint256 idA = pet.adopt(TRAITS_A);
        uint256 idB = pet.adopt(TRAITS_B);

        // 把双方亲密度拉到 >=100（13*8=104）
        _raiseAffinity(idA, 13);
        _raiseAffinity(idB, 13);

        bytes32 seed = keccak256("seed-xyz");
        bytes32 salt = keccak256("salt-abc");
        bytes32 commitHash = keccak256(abi.encodePacked(seed, salt));

        pet.commitBreed(idA, idB, commitHash);
        uint256 childId = pet.revealBreed(idA, idB, seed, salt);

        assertEq(childId, 3);
        assertEq(pet.ownerOf(childId), alice);

        (,,,,, bytes32 childTraits) = pet.stateOf(childId);
        // 子代基因应不同于双亲（混合 + 区块熵）
        assertTrue(childTraits != TRAITS_A && childTraits != TRAITS_B);
        vm.stopPrank();
    }

    function test_BreedAffinityTooLowReverts() public {
        vm.startPrank(alice);
        uint256 idA = pet.adopt(TRAITS_A);
        uint256 idB = pet.adopt(TRAITS_B);
        bytes32 commitHash = keccak256("whatever");
        vm.expectRevert("Affinity too low to breed");
        pet.commitBreed(idA, idB, commitHash);
        vm.stopPrank();
    }

    function test_RevealWithWrongSeedReverts() public {
        vm.startPrank(alice);
        uint256 idA = pet.adopt(TRAITS_A);
        uint256 idB = pet.adopt(TRAITS_B);
        _raiseAffinity(idA, 13);
        _raiseAffinity(idB, 13);

        bytes32 seed = keccak256("seed-xyz");
        bytes32 salt = keccak256("salt-abc");
        bytes32 commitHash = keccak256(abi.encodePacked(seed, salt));
        pet.commitBreed(idA, idB, commitHash);

        vm.expectRevert("Breed not revealed");
        pet.revealBreed(idA, idB, keccak256("wrong-seed"), salt);
        vm.stopPrank();
    }

    function test_RevealWithoutCommitReverts() public {
        vm.startPrank(alice);
        uint256 idA = pet.adopt(TRAITS_A);
        uint256 idB = pet.adopt(TRAITS_B);
        _raiseAffinity(idA, 13);
        _raiseAffinity(idB, 13);
        vm.expectRevert("Breed not committed");
        pet.revealBreed(idA, idB, keccak256("seed"), keccak256("salt"));
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // 转移
    // ------------------------------------------------------------------
    function test_TransferPet() public {
        vm.prank(alice);
        uint256 id = pet.adopt(TRAITS_A);
        vm.prank(alice);
        pet.transferPet(bob, id);
        assertEq(pet.ownerOf(id), bob);
    }

    // ------------------------------------------------------------------
    // 睡眠时间窗
    // ------------------------------------------------------------------
    function test_FeedWhileSleepingReverts() public {
        vm.prank(alice);
        uint256 id = pet.adopt(TRAITS_A);
        // 前进到次日 23:00（睡眠窗内）
        vm.warp(START + 11 hours); // 12:00 + 11h = 23:00
        vm.prank(alice);
        vm.expectRevert("Pet is sleeping");
        pet.feed(id);
    }
}
