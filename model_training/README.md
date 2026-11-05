# 最终ResNet18训练、量化和NPU复现

本目录是完整系统中的模型模块。部署模型统一保存在外层`model`目录，不在本目录重复复制。以下命令从本目录执行。

## 文件与输入

- `models/best.pt`：最终FP32权重，30轮训练中按开发集整段macro-F1选中的第22轮。
- `models/ResNet18_radar.onnx`：对应冻结ONNX，输入NCHW `[1,1,10,512]`。
- `config`：训练参数、964/241/250份MAT的划分、标准化参数和九类顺序。
- `data/calibration`：54个真实训练校准窗口，每类6窗、54份不同MAT。
- `data/evaluation/heldout.npz`：完整固定测试集的标准化频谱帧和MAT边界。
- `results`：最终训练记录、PC及历史板端预测、三轮原始时延及精简模型对照。

一次输入是单通道连续10帧×512点。全局标准化`(x-137.53303464225368)/10.262633165907761`在模型外执行一次；包内校准、参考和测试输入已标准化。航迹不进入网络。

## PC运行与精度复核

建议使用独立Python 3.8—3.11部署环境，依赖为`requirements_pc.txt`。训练使用CUDA版PyTorch及torchvision，原GPU环境参考`requirements_training_reference.txt`。不必改动已有可用训练环境。

```powershell
python -m pip install -r requirements_pc.txt
python -B src/predict.py
python -B src/evaluate.py --partition heldout --engine saved_board
python -B src/evaluate.py --partition heldout --engine onnx --out runs/onnx_heldout.json
```

`saved_board`只是重算历史真实板端输出，不调用开发板，应得到6093/7239窗、230/250整段正确；`onnx`会重新推理全部7239窗，冻结FP32结果为6152/7239窗、229/250整段正确。INT8 Host和板端整段均为92%，但窗口类别不必逐一一致。

默认例子读取已经标准化的FTMP；预测原始MAT时使用`--input <MAT文件> --start 0`，MAT会自动标准化。普通BIN/NPY只有在保存原始幅值时才加`--raw`，不能对已标准化输入重复处理。

整段判决为同一MAT全部合法步长1窗口的softmax概率等权平均；GUI每文件任务只预测一个指定窗口。92%整段指标不能替代单窗指标或精选样例表现。

## 重新训练

完整LSS-HSR-L原始数据另备，`--dataset-root`指向直接包含`train`和`validation`的目录。训练仅读取划分中的训练和开发MAT。

```powershell
python -B src/train.py --dataset-root "数据集根目录" --out runs/retrain_seed42
```

固定配置：仅频谱、seed42、30轮、batch64、AdamW、初始学习率0.001、weight decay 0.01、余弦退火至0.00001、普通交叉熵。每轮6153次“类别→MAT→合法整数起点”均衡随机抽窗，开发集全部6836窗用于选权重。输出位于新运行目录下`training/resnet18`；同命令可恢复中断训练。

包内不重复附开发频谱缓存；需要重新推理开发集时，可生成：

```powershell
python -B src/prepare_evaluation.py --dataset-root "数据集根目录" --partition development
python -B src/evaluate.py --partition development --engine onnx --out runs/onnx_development.json
```

保存结果模式`saved_fp32`、`saved_host`、`saved_board`均可直接复算开发或固定测试指标，不需要重新生成输入缓存。不能将已多次评价的固定测试集称为新增盲测。

## 导出、校准与Icraft五阶段

使用配套PyTorch、ONNX及ONNX Runtime环境执行导出；新产物不覆盖冻结模型：

```powershell
python -B src/export_onnx.py --out runs/export/ResNet18_radar.onnx
python -B src/compile_icraft.py --cli-dir "Icraft的CLI目录" --out runs/icraft_rebuild
```

Icraft版本采用已验证的3.36.1。Parse→Optimize→Quantize→Adapt→Generate；量化参数INT8/per-channel/KLD、校准batch=6、`no_transinput=true`，应用接口仍为FP32，模型运行batch为1。量化中间图可由脚本重建，无需全部存进提交包。

校准输入已提供，不必重复选样。需要复现54窗来源时：

```powershell
python -B src/select_calibration.py --dataset-root "数据集根目录" --out runs/calibration_reselected
```

程序只读取训练MAT，按原八项频谱统计量和每类六中心聚类选样，核对MAT、起点及输入SHA256。完整原始数据集不随包分发。

## 独立NPU运行

完整应用的TCP/PL/UART入口见外层README。以下为实际ZG330板上的独立模型验证，需要已安装配套SDK，且其他NPU程序已经正常停止：

```bash
PYTHONDONTWRITEBYTECODE=1 python3 src/infer_npu.py --out runs/npu_request_001
PYTHONDONTWRITEBYTECODE=1 python3 src/evaluate.py --partition heldout --engine npu --out runs/npu_heldout.json
```

独立SDK调用从外层`model`读取同一份最终ZG JSON/RAW。第一次命令默认54次预热、1080次单窗口重复请求，保留reset和输出等待；这是功能核对与重复单窗测速，不等同于原108个输入、三轮独立对照。SDK均值3.0841ms来自保留的历史对照，排除外部PL、网络和显示，不能直接代替整机任务时间。

全部生成结果写入`runs`。本次整合没有再次上板，也没有重新训练或量化交付模型；已冻结产物与包装代码验证分别记录。
