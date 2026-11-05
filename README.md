# PS PL NPU协同的雷达频谱目标识别系统

本包整合PC上位机、PS/PL通信工程、最终ResNet18模型及训练、校准量化和实验复现材料。输入为LSS-HSR-L公开多普勒频谱，九类为UAV1、UAV2、UAV3、UAV4、Bird、Birds、Wing Bird、Rotate、Car。

一次模型输入为连续10帧×512频点的单通道FP32数值张量，内部采用INT8量化计算，应用输出为9个FP32 logits。配套航迹仅供PC显示，不参与分类。

## 目录

|目录/文件|用途|
|---|---|
|`上位机`|PC GUI、TCP任务、结果归档、配套轨迹查看及离线界面示例|
|`ps_code/lss_hsrv3_timing`|PS常驻程序、PL控制、NPU接口、UART显示与历史查询|
|`prj`|PL工程、RTL、约束、IP/网表及构建脚本|
|`model`、`config`|完整应用与独立SDK调用共用的最终ResNet18 ZG模型及配置|
|`dataset`|九类各两组BIN/JSON演示输入，共18组|
|`sd`|原工程配套启动组件，不是完整Linux系统镜像|
|`model_training`|最终训练代码、PT、ONNX、54窗校准、完整固定测试频谱及实验结果|
|`docs`|部署参考、交付边界及串口屏资源说明|
|`AI_COLLABORATION_SUMMARY.md`|无私人路径和连接信息的团队AI协作过程摘要|
|`SUBMISSION_MANIFEST.json`、`verify_submission.py`|文件大小与SHA256完整性检查|

## 1. 解压后先检查

从解压后的项目根目录执行，Python标准库即可，不需要Torch或开发板：

```powershell
python -B verify_submission.py
```

出现`SUBMISSION_VERIFIED`说明清单中的文件完整。首次运行前先核对，再进行生成日志或重新构建等操作；自行修改源码后应另存工作副本并重新建立相应校验，不绕过构建检查。

## 2. PC上位机与演示

PC上位机使用Python 3.10以上及Tcl/Tk，双击`上位机/启动上位机.cmd`即可。它只使用标准库，不要求安装模型训练依赖。

启动自检也可从项目根目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./上位机/start_gui.ps1 -SelfTest
```

板端服务启动后，在GUI填写实际板卡地址和端口连接，添加`dataset`中的BIN，保留同名JSON，选择起始帧后发送。已组合保存的航迹和标注由PC解析，只有频谱上传给分类网络。JSON不可与不同BIN混用。

每个GUI文件任务推理一个指定10帧窗口；真实预测看任务输出或实体串口屏。发送类别和参考图片红框来自标注。离线examples用于界面检查，不代表当前ResNet18真实板端推理。

## 3. 板端应用

需要配套FMQL30TAI/BSP/PL、ARM64 Linux、Icraft 3.36.1开发及运行环境、C++17构建工具和CMake 3.16以上。完整镜像、SDK安装包不放入代码包，基础环境不齐时先按平台资料配置。详细说明见`docs/从零部署参考.md`。

将整个工程上传至一个可写目录，保留目录层级。从板端项目根目录执行：

```bash
cd ps_code/lss_hsrv3_timing
bash build_on_board.sh
bash run_timing.sh
```

构建使用单线程；小内存板卡编译前按部署参考启用已有或新建的编译swap。构建成功只表示源码、参数和动态库检查通过，不表示硬件推理已验收。

两个运行脚本均已默认选择外层`config/resnet18_sjp.json`。连接串口屏时，用下面的命令替代`run_timing.sh`，串口设备按实际识别结果选择：

```bash
bash run_hmi.sh /dev/ttyACM0
```

两种入口不要同时启动。当前任务处理流程为：PC上传→PS接收校验并选窗→PL缓存、搬运和写后读回→PS整窗比较→NPU推理及输出等待→结果回传PC并更新串口屏→任务清理和下一任务准入。

串口屏源码、控件表及事件协议已提供；原生HMI工程和TFT下载文件尚未在收到的材料中找到。使用兼容已烧录屏幕可继续联调，从空白屏完整复现还需补充资源，见`docs/交付边界与串口屏说明.md`。

## 4. 模型复现

从项目根目录执行：

```powershell
cd model_training
python -B src/predict.py
python -B src/evaluate.py --partition heldout --engine saved_board
python -B src/evaluate.py --partition heldout --engine onnx --out runs/onnx_heldout.json
```

这部分需要独立的模型部署Python环境，依赖及训练、ONNX导出、54窗校准、Icraft五阶段和NPU独立调用见`model_training/README.md`。

包内同时保留最终`best.pt`与ONNX。完整原始训练MAT另备；固定测试集的标准化频谱已随包提供，复核250份MAT的精度不依赖原电脑路径。无需保留全部训练轮次的checkpoint、优化器恢复状态、其他候选模型权重或虚拟环境。

## 5. 固定结果与计时口径

固定测试集来自原Validation的250份MAT、7239窗。独立SDK板端实验：

|模型|单窗准确率|整段准确率|SDK均值/10帧窗口|
|---|---:|---:|---:|
|最终ResNet18|84.17%|92.00%|3.0841ms|
|ResNet34，对照|85.21%|92.00%|5.0372ms|
|ResNet50，对照|79.51%|88.00%|6.3679ms|

整段按同一MAT全部合法步长1窗口的softmax等权平均，ResNet18为230/250正确；单窗为6093/7239。FP32 ONNX整段为229/250，量化Host及板端为230/250。18组演示文件不能用来计算92%识别率。

SDK请求含Tensor构造、reset、forward及输出就绪等待、结果读回，不含外部PL、网络与显示，不等于纯硬件算子或整机端到端时间。原始预测及三轮时延CSV在模型模块的`results`中，保存结果复算不等于新跑板端。

## 6. 本次交付整合的范围

原有PS核心、PL/IP及启动组件保留，最终JSON/RAW、PT、ONNX和数据BIN保持冻结内容；修正默认模型、上位机样例入口，补充模型复现材料和说明，清理生成日志及私人路径元数据，并更新校验。

本次仅进行PC侧核对和打包，没有重新连接开发板、重建PL或烧录屏幕。新板实际部署仍需使用匹配系统/硬件验收。当前系统为公开频谱文件回放，不宣称完成实时射频采集和前端FFT流程。
