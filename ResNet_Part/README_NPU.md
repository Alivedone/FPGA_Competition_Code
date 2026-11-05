# PS PL NPU协同的雷达频谱目标识别系统

本仓库补充作品的研究过程、实验依据、技术报告和展示材料。最终运行源码及部署模型以赛事提交代码包为准，本补充目录不重复收录完整PL/IP、SDK或系统镜像。

使用LSS-HSR-L公开频谱完成九类识别。单次输入为连续10帧×512点的单通道数值张量，按训练集全局标量统计标准化；航迹只供显示。系统由PC上位机、PS接收调度、PL缓存搬运与核对、ZG330 NPU及串口屏协同构成。

## 最终模型与结果

|模型|固定测试单窗准确率|整段准确率|SDK请求均值/10帧窗口|
|---|---:|---:|---:|
|**最终ResNet18**|84.17%|92.00%|3.0841ms|
|ResNet34，对照|85.21%|92.00%|5.0372ms|
|ResNet50，对照|79.51%|88.00%|6.3679ms|

固定测试为250份MAT、7239窗；整段对每份MAT全部合法窗口softmax等权平均。SDK时间包含请求构造、reset、forward/等待及读回，不含外部PL、网络和显示，不能当作整机端到端延迟。当前演示属于公开频谱文件回放。

## 从这里阅读

|目录|内容|
|---|---|
|[docs](docs)|公开版技术报告、AI协作说明、实验阶段与证据口径|
|[training_strategies](training_strategies)|8次训练策略/种子实验的配置、曲线、指标和保存预测|
|[early_backbones](early_backbones)|早期20轮ResNet/Res2Net骨干探索，与最终30轮选型分开|
|[calibration](calibration)|历史ResNet34校准A/B/C选择及完整开发集结果|
|[model_comparison](model_comparison)|最终三模型的训练、浮点/Host/板端精度及三轮时延证据|
|[npu_optimization](npu_optimization)|历史工程调用优化、A—F逐项实验、原版与F完整固定测试对照|
|[media](media)|已清理备注路径的展示PPT、公开截图和频谱输入图解|
|[tools](tools)|仅用保存输出重算指标的独立核验脚本|

![九类频谱窗口示例](media/nine_class_spectrum_examples.png)

## 大文件附件

在本仓库的[Releases](https://github.com/Alivedone/FPGA_Competition_Code/releases)发布附件：

- `research_checkpoints.rar`：6份代表性研究权重，早期20轮4份，最终策略ResNet34/50候选2份。最终ResNet18已在赛事代码包中，不在附件重复。
- `radar_demo_final.mp4`：团队选定的成片副本；保留既有视频画面和作品署名，未重新剪辑。

这些文件由仓库维护者手动上传后才可从Releases获取。源文件区不需要放大型RAR或视频。

## 独立复算

在包含NumPy的Python环境中，从本仓库根目录执行：

```bash
python -B tools/verify_research_results.py
```

脚本先核对公开文件清单，再从NPZ和CSV复算训练、校准、三模型与原版/F的结果，不训练模型、不访问网络或开发板。复算保存结果不等于新跑硬件实验。

## 数据与发布说明

不同阶段的模型、训练条件和计时范围不同，不能把历史最高数字直接当作最终模型结果。训练/开发按完整MAT划分；固定测试集已被多轮评价，不称为新盲测。

公开JSON的私人路径已脱敏，NPZ、CSV和权重保持数值内容。历史报告内的来源散列仍指原始记录，公开文件当前身份以`PUBLIC_MANIFEST.json`为准。PPT备注与文档属性已清理，PDF和PPT截图中的本地目录、示例连接地址已遮盖；原始稿保留在团队工作区。媒体中的作品署名沿用既有版本，视频为原成片副本，发布前仍应人工复核画面和音轨。

不附原始数据集全集、厂商SDK、完整系统镜像、SSH材料或其他路线。第三方数据、论文与平台资料遵循各自的引用和授权要求；本次整理不代团队选择新的开源许可证。
