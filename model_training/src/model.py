"""Final spectrum-only ResNet18; state_dict keys match the frozen checkpoint."""
import torch
from torch import nn
from torchvision.models import resnet18
class SpectrumNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.backbone=resnet18(weights=None)
        self.backbone.conv1=nn.Conv2d(1,64,3,stride=(1,2),padding=1,bias=False)
        self.backbone.maxpool=nn.Identity()
        self.backbone.fc=nn.Identity()
        self.classifier=nn.Linear(512,9)
    def forward(self,x):return self.classifier(self.backbone(x))
def load_model(checkpoint=None):
    from common import ROOT
    state=torch.load(str(checkpoint or ROOT/'models/best.pt'),map_location='cpu',weights_only=True)
    model=SpectrumNet();model.load_state_dict(state['state_dict'],strict=True)
    return model.eval()
