# 追光球：三轮随机平滑追踪

每轮25秒：基础自由、连续变速、复杂变速与遮挡。RandomPath.js 使用种子化航点、Catmull-Rom 样条和弧长采样，以连续速度积分推进。pursuit.path_plan 记录 seed、航点和速度计划；可用相同 seed 重放。通过 pointer 入口进入，评分保持 MAE/RMSE、容差占比与重捕获指标。
