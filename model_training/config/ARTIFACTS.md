# 模型文件对应关系

本模块使用以下冻结材料：

|产物|位置与用途|
|---|---|
|训练权重|本模块`models/best.pt`，FP32，ResNet18第22轮|
|ONNX|本模块`models/ResNet18_radar.onnx`，opset11|
|ZG JSON/RAW|外层`model`目录，PS程序及独立NPU入口共用|
|预处理及接口|本模块`config/interface.json`和外层ResNet18配置|
|输入输出对照|本模块`data/reference_*`，27窗；不替代完整测试集|

未复制量化Host的中间JSON/RAW、其他网络权重和全部训练过程checkpoint。需要重新生成中间模型时执行编译脚本；保存的Host预测仍可用于指标复算。最终模型身份由外层`SUBMISSION_MANIFEST.json`核对。
