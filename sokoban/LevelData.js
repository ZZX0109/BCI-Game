.pragma library

// 本文件由 tools/verify_sokoban_levels.py --emit 生成，BFS 已验证可解。
// Legend: '#' wall '.' goal '$' box '@' player ' ' floor
var levels = [
    { id: "S01", version: 1, name: "Guide", goal: "直线接近并推动（单次离散动作教学）", grid: ["########", "#      #", "# @$.  #", "#      #", "########"] },
    { id: "S02", version: 1, name: "Corner", goal: "需从侧边绕行；存在非目标墙角（死锁学习）", grid: ["########", "#      #", "# $    #", "# #    #", "#.##   #", "#  @   #", "########"] },
    { id: "S03", version: 1, name: "Route", goal: "路径绕过墙体，至少两个方向切换（原包地图）", grid: ["########", "#      #", "#  $   #", "#  @  .#", "#      #", "########"] },
    { id: "S04", version: 1, name: "TwoBoxes", goal: "两个目标，先后推动次序影响解", grid: ["#########", "#       #", "#  $  . #", "# @$  . #", "#       #", "#########"] },
    { id: "S05", version: 1, name: "Challenge", goal: "选择错误可能死锁；提供撤销恢复", grid: ["########", "#      #", "# .  . #", "# $$   #", "#  @   #", "#      #", "########"] }
]
