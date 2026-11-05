"""Reproduce five Icraft CLI stages using final ONNX and frozen calibration."""
import argparse,json,shutil,subprocess,tempfile
from pathlib import Path
from common import ROOT,read,write,sha
NAME='ResNet18_radar'
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--cli-dir',type=Path,help='Icraft CLI bin directory; otherwise search PATH')
    ap.add_argument('--onnx',type=Path,default=ROOT/'models/ResNet18_radar.onnx')
    ap.add_argument('--out',type=Path,required=True)
    a=ap.parse_args();out=a.out.resolve()
    if out.exists():raise FileExistsError('Choose fresh --out: '+str(out))
    def exe(stage):
        name='icraft-'+stage
        p=shutil.which(name,path=str(a.cli_dir) if a.cli_dir else None)
        if p is None:raise RuntimeError('Missing Icraft executable '+name)
        return p
    for stage in ['parse','optimize','quantize','adapt','generate','run']:exe(stage)
    out.mkdir(parents=True);dest=out/'icraft';dest.mkdir();logs=out/'logs';logs.mkdir()
    report=dict(onnx_sha256=sha(a.onnx),stages=[],board_executed=False)
    def run(stage,flags,log):
        argv=[exe(stage)]+list(map(str,flags))
        with log.open('wb') as f:subprocess.run(argv,cwd=str(out),stdout=f,stderr=subprocess.STDOUT,check=True)
        return dict(stage=stage,command=argv,returncode=0)
    stages=[('parse',['--net_name',NAME,'--network',a.onnx.resolve(),'--framework','Onnx','--target','zhuge',
        '--inputs','1,10,512,1','--inputs_layout','NHWC','--inputs_dtype','FP32','--pre_method','nop',
        '--pre_scale','1','--pre_mean','0','--channel_swap','0','--jr_path',dest],'parsed'),
        ('optimize',['--target','zhuge','--json',dest/(NAME+'_parsed.json'),'--raw',dest/(NAME+'_parsed.raw'),'--jr_path',dest],'optimized'),
        ('quantize',None,'quantized'),
        ('adapt',['--target','zhuge','--json',dest/(NAME+'_quantized.json'),'--raw',dest/(NAME+'_quantized.raw'),'--jr_path',dest],'adapted'),
        ('generate',['--json',dest/(NAME+'_adapted.json'),'--raw',dest/(NAME+'_adapted.raw'),'--jr_path',dest],'ZG')]
    for stage,flags,suffix in stages:
        with tempfile.TemporaryDirectory(prefix='activation_',dir=str(out)) as temp:
            if stage=='quantize':
                cache=Path(temp);listing=[]
                for r in read(ROOT/'data/calibration_selection.json')['records']:
                    inp=ROOT/r['input_file'];assert sha(inp)==r['input_sha256']
                    work=cache/r['sample_id']
                    run('run',['--json',dest/(NAME+'_optimized.json'),'--raw',dest/(NAME+'_optimized.raw'),
                        '--input',inp,'--backends','Host','--dump_format','SFB','--log_path',work],logs/(r['sample_id']+'.log'))
                    if not (work/NAME/'ftmpSFB/0.ftmp').exists():raise RuntimeError('Missing activation dump')
                    listing.append(r['sample_id']+'/'+NAME+'/ftmpSFB')
                file=cache/'files.txt';file.write_text('\n'.join(listing)+'\n',encoding='utf-8')
                flags=['--target','zhuge','--json',dest/(NAME+'_optimized.json'),'--raw',dest/(NAME+'_optimized.raw'),
                    '--jr_path',dest,'--forward_mode','ftmp','--forward_dir',cache,'--forward_list',file,
                    '--qdtype','int8','--per','channel','--saturation','kld','--batch','6','--no_transinput','true']
            entry=run(stage,flags+['--log_path',logs/stage],logs/(stage+'.log'))
            entry['outputs']={p.relative_to(out).as_posix():sha(p) for p in [dest/(NAME+'_'+suffix+'.'+e) for e in ['json','raw']]}
            report['stages'].append(entry);write(out/'compile_report.json',report)
        print('COMPLETED',stage,flush=True)
    report['status']='completed';write(out/'compile_report.json',report)
if __name__=='__main__':main()
