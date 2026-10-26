/// 低端机检测（ui-glass-motion.md §2.4）。
///
/// 安卓低端机（RAM ≤ 3GB）自动把玻璃降级为纯色、关循环动画。
/// M1 阶段先按非低端处理；M8 接 method channel 读 ActivityManager.memoryClass
/// （<= 192 ≈ 3GB）后替换这里的实现。
bool get isLowEndDevice => false;
