// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SoulPet —— 有状态的链上 AI 伴侣宠物
/// @notice 一只活在链上、有记忆、会成长、会社交的电子宠物。
///         饥饿、心情、亲密度、进化阶段、性格基因全部为链上状态；
///         由链下的 AI Agent "附身"，读取这些状态决定语气与行为。
/// @dev 本合约完全自包含：内置轻量 NFT 归属、状态机与
///      commit-reveal + 区块熵的繁育随机，不依赖任何外部库或预言机。
///      注意：内置随机为黑客松级别，并非密码学级 VRF。
contract SoulPet {
    // ---------------------------------------------------------------------
    // 数据结构
    // ---------------------------------------------------------------------

    /// @notice 单只宠物的链上灵魂状态
    struct Pet {
        uint64 birth; // 出生时间戳
        uint64 lastFed; // 上次喂食时间戳（仅用于喂食冷却）
        uint64 lastDecay; // 饥饿/心情衰减的结算基准时间
        uint64 lastInteract; // 上次主人互动时间戳（用于判定冷落）
        uint16 hunger; // 饥饿度：0=饱，100=饿（随时间增长）
        uint16 mood; // 心情：0-100（随冷落下降）
        uint32 affinity; // 与主人的亲密度（累计互动，只增不减）
        uint8 stage; // 进化阶段：0=蛋，逐级进化
        bytes32 traits; // 性格基因（影响 AI 语气，繁育时混合）
        bytes32 memoryRoot; // 记忆 Merkle 根（链下记忆的链上锚点）
    }

    // ---------------------------------------------------------------------
    // 存储
    // ---------------------------------------------------------------------

    /// @notice id => 宠物状态
    mapping(uint256 => Pet) public pets;

    /// @notice id => 主人地址（轻量 NFT 归属，0 地址表示不存在）
    mapping(uint256 => address) public ownerOf;

    /// @notice 下一个待分配的宠物 id（从 1 开始，0 视为无效）
    uint256 public nextId = 1;

    /// @notice 繁育承诺：将一对父母的有序 key 映射到提交的哈希
    mapping(bytes32 => bytes32) public breedCommit;

    // ---------------------------------------------------------------------
    // 可调参数（常量，便于阅读与测试）
    // ---------------------------------------------------------------------

    uint256 public constant FEED_COOLDOWN = 1 hours; // 两次喂食的最小间隔
    uint256 public constant HUNGER_PER_HOUR = 5; // 每小时增长的饥饿度
    uint256 public constant MOOD_DROP_PER_HOUR = 3; // 每小时下降的心情
    uint256 public constant NEGLECT_THRESHOLD = 2 days; // 超过此时长未互动视为被冷落
    uint256 public constant BREED_MIN_AFFINITY = 100; // 繁育所需的最低亲密度

    // 进化所需条件（阶段越高要求越高，这里用线性阈值简化）
    uint256 public constant EVOLVE_MIN_AGE = 1 days; // 每次进化的最小年龄增量
    uint32 public constant EVOLVE_MIN_AFFINITY = 50; // 每阶段所需亲密度增量
    uint8 public constant MAX_STAGE = 4; // 最高进化阶段

    // 一天中的睡眠时间窗（UTC 小时）：22:00 - 06:00 宠物在睡觉，无法喂食/陪玩/串门
    uint256 public constant SLEEP_START_HOUR = 22;
    uint256 public constant SLEEP_END_HOUR = 6;

    // ---------------------------------------------------------------------
    // 事件
    // ---------------------------------------------------------------------

    event Adopted(address indexed owner, uint256 indexed id, bytes32 traits);
    /// @param kind 互动类型：0=feed，1=play，2=care
    event Interacted(uint256 indexed id, uint8 kind);
    event Evolved(uint256 indexed id, uint8 stage);
    event MemoryUpdated(uint256 indexed id, bytes32 root);
    event Visited(uint256 indexed id, uint256 indexed otherId);
    event Bred(uint256 indexed parentA, uint256 indexed parentB, uint256 childId);
    event Transferred(uint256 indexed id, address indexed from, address indexed to);

    // ---------------------------------------------------------------------
    // 修饰符
    // ---------------------------------------------------------------------

    /// @dev 要求宠物存在
    modifier exists(uint256 id) {
        require(ownerOf[id] != address(0), "Pet does not exist");
        _;
    }

    /// @dev 要求调用者是该宠物的主人
    modifier onlyOwner(uint256 id) {
        require(ownerOf[id] == msg.sender, "Not pet owner");
        _;
    }

    // ---------------------------------------------------------------------
    // 领养
    // ---------------------------------------------------------------------

    /// @notice 领养一只全新的 SoulPet
    /// @param traits 性格基因（可由前端随机生成；影响 AI 语气）
    /// @return id 新宠物的 id
    function adopt(bytes32 traits) external returns (uint256 id) {
        id = _spawn(msg.sender, traits);
        emit Adopted(msg.sender, id, traits);
    }

    /// @dev 铸造一只新宠物并初始化其状态，供领养与繁育复用。
    function _spawn(address to, bytes32 traits) internal returns (uint256 id) {
        id = nextId++;
        ownerOf[id] = to;

        Pet storage p = pets[id];
        uint64 nowTs = uint64(block.timestamp);
        p.birth = nowTs;
        // lastFed 故意保留默认 0，使得首次喂食不受冷却限制
        p.lastDecay = nowTs;
        p.lastInteract = nowTs;
        p.hunger = 0; // 刚领养/出生时是饱的
        p.mood = 80; // 初始心情不错
        p.affinity = 0;
        p.stage = 0; // 从蛋开始
        p.traits = traits;
    }

    // ---------------------------------------------------------------------
    // 互动：喂食 / 陪玩 / 照料
    // ---------------------------------------------------------------------

    /// @notice 喂食。可附带 PHRS 作为"零食"，有冷却时间。
    /// @dev 喂食会清空饥饿、提升心情与亲密度。
    function feed(uint256 id) external payable exists(id) onlyOwner(id) {
        Pet storage p = pets[id];
        require(!_isSleeping(), "Pet is sleeping");
        require(block.timestamp >= p.lastFed + FEED_COOLDOWN, "Too soon to feed");

        _settle(p); // 先把随时间累积的衰减结算到存储

        p.hunger = 0; // 吃饱了
        p.mood = _clampMood(uint256(p.mood) + 15);
        p.affinity += 5;
        p.lastFed = uint64(block.timestamp);
        p.lastInteract = uint64(block.timestamp);

        emit Interacted(id, 0);
    }

    /// @notice 陪玩。提升心情与亲密度，但会消耗一点体力（略增饥饿）。
    function play(uint256 id) external exists(id) onlyOwner(id) {
        Pet storage p = pets[id];
        require(!_isSleeping(), "Pet is sleeping");

        _settle(p);

        p.mood = _clampMood(uint256(p.mood) + 20);
        p.affinity += 8;
        p.hunger = _clampHunger(uint256(p.hunger) + 5);
        p.lastInteract = uint64(block.timestamp);

        emit Interacted(id, 1);
    }

    /// @notice 照料（梳毛/清洁等）。温和地恢复心情、提升亲密度。
    function care(uint256 id) external exists(id) onlyOwner(id) {
        Pet storage p = pets[id];

        _settle(p);

        p.mood = _clampMood(uint256(p.mood) + 10);
        p.affinity += 3;
        p.lastInteract = uint64(block.timestamp);

        emit Interacted(id, 2);
    }

    // ---------------------------------------------------------------------
    // 进化
    // ---------------------------------------------------------------------

    /// @notice 在满足年龄、亲密度与心情条件时进化到下一阶段。
    /// @dev 任何人都可触发（通常由附身 Agent 在条件满足时自动调用）。
    function evolve(uint256 id) external exists(id) {
        Pet storage p = pets[id];
        require(p.stage < MAX_STAGE, "Already max stage");

        _settle(p);

        uint8 nextStage = p.stage + 1;
        // 阶段越高，要求的最小年龄与累计亲密度越高
        require(block.timestamp >= p.birth + EVOLVE_MIN_AGE * nextStage, "Too young to evolve");
        require(p.affinity >= EVOLVE_MIN_AFFINITY * nextStage, "Affinity too low to evolve");
        require(p.mood >= 50, "Mood too low to evolve");

        p.stage = nextStage;
        emit Evolved(id, nextStage);
    }

    // ---------------------------------------------------------------------
    // 记忆锚点
    // ---------------------------------------------------------------------

    /// @notice 把本次对话/记忆的 Merkle 根写到链上（细节存链下，链上仅锚定）。
    /// @dev 通常由附身 Agent（持有主人私钥或被授权）调用。
    function commitMemory(uint256 id, bytes32 root) external exists(id) onlyOwner(id) {
        pets[id].memoryRoot = root;
        pets[id].lastInteract = uint64(block.timestamp);
        emit MemoryUpdated(id, root);
    }

    // ---------------------------------------------------------------------
    // 社交：串门
    // ---------------------------------------------------------------------

    /// @notice 让自己的宠物去拜访另一只宠物，双方心情都会提升。
    /// @param id 自己的宠物
    /// @param otherId 被拜访的宠物
    function visit(uint256 id, uint256 otherId) external exists(id) onlyOwner(id) {
        require(ownerOf[otherId] != address(0), "Other pet does not exist");
        require(id != otherId, "Cannot visit self");
        require(!_isSleeping(), "Pet is sleeping");

        Pet storage a = pets[id];
        Pet storage b = pets[otherId];

        _settle(a);
        _settle(b);

        // 社交让双方都开心，并积累亲密度
        a.mood = _clampMood(uint256(a.mood) + 12);
        b.mood = _clampMood(uint256(b.mood) + 12);
        a.affinity += 4;
        b.affinity += 4;
        a.lastInteract = uint64(block.timestamp);
        b.lastInteract = uint64(block.timestamp);

        emit Visited(id, otherId);
    }

    // ---------------------------------------------------------------------
    // 繁育：commit-reveal + 区块熵（自包含随机）
    // ---------------------------------------------------------------------

    /// @notice 第一步：提交繁育承诺（哈希）。两只宠物需满足亲密度门槛。
    /// @param idA 父本（必须由调用者拥有）
    /// @param idB 母本（必须由调用者拥有，黑客松版要求同一主人或被授权）
    /// @param commitHash keccak256(abi.encodePacked(seed, salt)) —— seed/salt 链下保密
    function commitBreed(uint256 idA, uint256 idB, bytes32 commitHash)
        external
        exists(idA)
        exists(idB)
        onlyOwner(idA)
        onlyOwner(idB)
    {
        require(idA != idB, "Cannot breed with self");
        Pet storage a = pets[idA];
        Pet storage b = pets[idB];
        require(a.affinity >= BREED_MIN_AFFINITY && b.affinity >= BREED_MIN_AFFINITY, "Affinity too low to breed");

        breedCommit[_breedKey(idA, idB)] = commitHash;
    }

    /// @notice 第二步：揭示并完成繁育，产出一只继承双亲基因的新宠。
    /// @dev 子代基因 = keccak256(seed, salt, block.prevrandao, parentA.traits, parentB.traits)。
    ///      区块熵（block.prevrandao）确保即使 seed 泄露也带有不可预测性。
    ///      非密码学级 VRF，黑客松够用。
    /// @return childId 新宠物的 id
    function revealBreed(uint256 idA, uint256 idB, bytes32 seed, bytes32 salt)
        external
        exists(idA)
        exists(idB)
        onlyOwner(idA)
        onlyOwner(idB)
        returns (uint256 childId)
    {
        bytes32 key = _breedKey(idA, idB);
        bytes32 commitHash = breedCommit[key];
        require(commitHash != bytes32(0), "Breed not committed");
        require(keccak256(abi.encodePacked(seed, salt)) == commitHash, "Breed not revealed");

        // 清除承诺，防止重放
        delete breedCommit[key];

        // 混合双亲基因 + 区块熵，得到子代性格基因，并铸造新宠
        childId = _spawn(msg.sender, _mixTraits(idA, idB, seed, salt));

        emit Bred(idA, idB, childId);
    }

    // ---------------------------------------------------------------------
    // 转移（满足"可整只交易 / 可继承"）
    // ---------------------------------------------------------------------

    /// @notice 把宠物转移给新主人。
    function transferPet(address to, uint256 id) external exists(id) onlyOwner(id) {
        require(to != address(0), "Invalid recipient");
        address from = ownerOf[id];
        ownerOf[id] = to;
        emit Transferred(id, from, to);
    }

    // ---------------------------------------------------------------------
    // 只读视图
    // ---------------------------------------------------------------------

    /// @notice 读取宠物的"实时"状态（饥饿随时间增长、心情随冷落下降，纯链上计算）。
    /// @return owner 主人地址
    /// @return hunger 当前饥饿度（已结算衰减）
    /// @return mood 当前心情（已结算衰减）
    /// @return affinity 累计亲密度
    /// @return stage 进化阶段
    /// @return traits 性格基因
    function stateOf(uint256 id)
        external
        view
        exists(id)
        returns (address owner, uint16 hunger, uint16 mood, uint32 affinity, uint8 stage, bytes32 traits)
    {
        Pet memory p = pets[id];
        (uint16 h, uint16 m) = _projected(p);
        return (ownerOf[id], h, m, p.affinity, p.stage, p.traits);
    }

    /// @notice 把数值状态转述为一句中文心情语，供 AI Agent 直接转述给主人。
    function statusText(uint256 id) external view exists(id) returns (string memory) {
        Pet memory p = pets[id];
        (uint16 hunger, uint16 mood) = _projected(p);

        if (isNeglected(id)) {
            return unicode"它好久没见到你了，有点失落，你是不是不要它了……";
        }
        if (hunger >= 70) {
            return unicode"它现在很饿，正眼巴巴地等你喂食。";
        }
        if (mood >= 70) {
            return unicode"它现在非常开心，蹦蹦跳跳地黏着你。";
        }
        if (mood <= 30) {
            return unicode"它现在心情有点低落，需要你的陪伴。";
        }
        if (hunger >= 40) {
            return unicode"它有点饿了，想吃点东西。";
        }
        return unicode"它现在状态平稳，安静地待在你身边。";
    }

    /// @notice 宠物是否被冷落（超过阈值时长没有任何互动）。
    function isNeglected(uint256 id) public view exists(id) returns (bool) {
        return block.timestamp >= pets[id].lastInteract + NEGLECT_THRESHOLD;
    }

    // ---------------------------------------------------------------------
    // 内部工具
    // ---------------------------------------------------------------------

    /// @dev 根据距上次衰减结算的时间，计算"投影后"的饥饿与心情（不写存储）。
    function _projected(Pet memory p) internal view returns (uint16 hunger, uint16 mood) {
        uint256 elapsedHours = (block.timestamp - p.lastDecay) / 1 hours;

        uint256 h = uint256(p.hunger) + elapsedHours * HUNGER_PER_HOUR;
        uint256 moodDrop = elapsedHours * MOOD_DROP_PER_HOUR;
        uint256 m = uint256(p.mood) > moodDrop ? uint256(p.mood) - moodDrop : 0;

        hunger = _clampHunger(h);
        mood = _clampMood(m);
    }

    /// @dev 把随时间累积的衰减结算回存储，并刷新衰减基准时间。
    ///      只动衰减基准，不触碰 lastInteract（冷落计时）与 lastFed（喂食冷却）。
    function _settle(Pet storage p) internal {
        (uint16 h, uint16 m) = _projected(p);
        p.hunger = h;
        p.mood = m;
        p.lastDecay = uint64(block.timestamp);
    }

    /// @dev 把饥饿度限制在 [0,100]
    function _clampHunger(uint256 v) internal pure returns (uint16) {
        return v > 100 ? 100 : uint16(v);
    }

    /// @dev 把心情限制在 [0,100]
    function _clampMood(uint256 v) internal pure returns (uint16) {
        return v > 100 ? 100 : uint16(v);
    }

    /// @dev 判断当前是否处于睡眠时间窗（UTC 22:00-06:00）。
    function _isSleeping() internal view returns (bool) {
        uint256 hourOfDay = (block.timestamp / 1 hours) % 24;
        // 跨午夜区间：>=22 或 <6
        return hourOfDay >= SLEEP_START_HOUR || hourOfDay < SLEEP_END_HOUR;
    }

    /// @dev 混合双亲基因 + 区块熵，得到子代性格基因（非密码学级随机）。
    function _mixTraits(uint256 idA, uint256 idB, bytes32 seed, bytes32 salt) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(seed, salt, block.prevrandao, pets[idA].traits, pets[idB].traits));
    }

    /// @dev 生成一对父母的有序承诺 key（与传参顺序无关）。
    function _breedKey(uint256 idA, uint256 idB) internal pure returns (bytes32) {
        (uint256 lo, uint256 hi) = idA < idB ? (idA, idB) : (idB, idA);
        return keccak256(abi.encodePacked(lo, hi));
    }
}
