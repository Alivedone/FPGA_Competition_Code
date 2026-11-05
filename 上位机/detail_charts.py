"""Track radar and deferred class-image presentation. No extra dependencies."""
import json
import math
from pathlib import Path
import tkinter as tk
from class_labels import display_labels, CLASS_NAMES


def nice_step(span):
    raw=max(span/6,1e-9);base=10**math.floor(math.log10(raw))
    return next(n*base for n in (1,2,5,10) if n*base>=raw)


def ticks(lo,hi,step):
    first=math.ceil(lo/step);last=math.floor(hi/step)
    if last-first+1>60:raise ValueError('刻度间隔过小，请增大间隔或填0使用自动刻度')
    return [i*step for i in range(first,last+1)]


def draw_track(canvas, track, x_step=0., y_step=0.):
    canvas.delete('all');canvas.track_geometry=None
    w,h=max(canvas.winfo_width(),700),max(canvas.winfo_height(),280)
    if track is None:
        canvas.create_text(w/2,h/2,text='此任务没有关联轨迹',width=w*.5,justify='center',tags=('track_error',))
        return
    if not all(math.isfinite(v) and v>=0 for v in (x_step,y_step)):
        raise ValueError('刻度间隔需为非负有限数；0表示自动')
    rows,start=track['rows'],track['start_frame']
    absolute=[(row[1]*1000*math.sin(math.radians(row[2])),row[1]*1000*math.cos(math.radians(row[2]))) for row in rows]
    x0,y0=absolute[0];points=[(x-x0,y-y0) for x,y in absolute]
    xs=[p[0] for p in points];ys=[p[1] for p in points]
    left,right,top,bottom=80,w-30,35,h-60
    pw,ph=right-left,bottom-top
    extent=max(max(xs)-min(xs),max(ys)-min(ys),1.)
    scale=max((max(xs)-min(xs)+.2*extent)/pw,(max(ys)-min(ys)+.2*extent)/ph,.5/min(pw,ph))
    cx,cy=(max(xs)+min(xs))/2,(max(ys)+min(ys))/2
    xlo,xhi=cx-scale*pw/2,cx+scale*pw/2;ylo,yhi=cy-scale*ph/2,cy+scale*ph/2
    dx=x_step or nice_step(xhi-xlo);dy=y_step or nice_step(yhi-ylo)
    xt,yt=ticks(xlo,xhi,dx),ticks(ylo,yhi,dy)
    px=lambda x:left+(x-xlo)/scale
    py=lambda y:bottom-(y-ylo)/scale
    for x in xt:
        at=px(x);canvas.create_line(at,top,at,bottom,fill='#e2eaf0',tags=('track_grid',))
        canvas.create_text(at,bottom+17,text='%.5g'%x,tags=('x_tick',))
    for y in yt:
        at=py(y);canvas.create_line(left,at,right,at,fill='#e2eaf0',tags=('track_grid',))
        canvas.create_text(left-8,at,text='%.5g'%y,anchor='e',tags=('y_tick',))
    canvas.create_rectangle(left,top,right,bottom,outline='#7890a4')
    screen=[(px(x),py(y)) for x,y in points]
    for i,(x,y) in enumerate(screen):
        if i:
            previous=screen[i-1]
            canvas.create_line(*previous,x,y,fill='#2383af',width=2,tags=('track_segment',))
            if i in (3,6,9) and math.hypot(x-previous[0],y-previous[1])>8:
                canvas.create_line(*previous,x,y,fill='#bd7918',arrow='last',arrowshape=(8,10,4))
        canvas.create_oval(x-3,y-3,x+3,y+3,fill='#368dcc',outline='white',tags=('track_point',))
        canvas.create_text(x+7,y-9,text=str(start+i),anchor='w',fill='#526779',font=('Segoe UI',8),tags=('point_frame',))
    x,y=screen[0];canvas.create_oval(x-6,y-6,x+6,y+6,fill='#29b951',outline='white',tags=('track_start',))
    x,y=screen[-1];canvas.create_rectangle(x-6,y-6,x+6,y+6,fill='#ec553c',outline='white',tags=('track_end',))
    canvas.create_text((left+right)/2,h-15,text='X（m）',fill='#526779',font=('Microsoft YaHei UI',9))
    canvas.create_text(left-65,(top+bottom)/2,text='Y（m）',angle=90,fill='#526779')
    canvas.track_geometry=dict(points_m=points,screen_points=screen,xlim=(xlo,xhi),ylim=(ylo,yhi),x_step=dx,y_step=dy,metres_per_pixel=scale)


def draw_class_gallery(canvas, truth, assets):
    """Nine reference images in training label order; highlight metadata truth only."""
    canvas.delete('all');canvas.category_images=[];canvas.gallery_order=list(CLASS_NAMES)
    canvas.highlighted_class = truth if truth in CLASS_NAMES else None
    w,h=max(canvas.winfo_width(),900),max(canvas.winfo_height(),120)
    cell=w/len(CLASS_NAMES);assets=Path(assets)
    try:
        mapping=json.loads((assets/'class_images.json').read_text(encoding='utf-8'))
    except (OSError,ValueError):
        mapping={}
    for index,name in enumerate(CLASS_NAMES):
        left,right=index*cell+5,(index+1)*cell-5
        canvas.create_rectangle(left,5,right,h-5,outline='#e1e7ec',tags=('class_card',))
        try:
            filename=mapping.get(str(index),'class_%d.png'%index)
            if not isinstance(filename,str) or Path(filename).name!=filename or Path(filename).suffix.lower() not in ('.png','.gif'):
                raise ValueError('图片配置无效')
            photo=tk.PhotoImage(master=canvas,file=str(assets/filename))
            factor=max(1,math.ceil(photo.width()/max(1,cell-24)),math.ceil(photo.height()/max(1,h-50)))
            if factor>1:photo=photo.subsample(factor,factor)
            canvas.category_images.append(photo)
            canvas.create_image((left+right)/2,(h-26)/2,image=photo,tags=('class_image','class_image_%d'%index))
        except (OSError,ValueError,tk.TclError):
            canvas.create_text((left+right)/2,h/2,text=name+'\n图片不可用',width=cell-18,justify='center',tags=('image_placeholder',))
        canvas.create_text((left+right)/2,h-20,text=name,font=('Microsoft YaHei UI',10),fill='#143753',tags=('class_name','class_name_%d'%index))
        if name==canvas.highlighted_class:
            canvas.create_rectangle(left,5,right,h-5,outline='#e32636',width=3,tags=('sent_class_highlight','sent_class_%d'%index))


def draw_class_image(canvas, result, assets):
    canvas.delete('all');canvas.category_image=None
    w,h=max(canvas.winfo_width(),200),max(canvas.winfo_height(),140)
    if result['kind'] != 'classification':
        canvas.create_text(w/2,h/2,text='诊断模型没有类别图像');return
    label=str(result['labels'][result['index']]);assets=Path(assets)
    display_label=display_labels(result['labels'])[result['index']]
    canvas.create_text(w/2,18,text='预测类别：%s · 参考图像' % display_label,font=('Microsoft YaHei UI',12,'bold'),fill='#143753')
    mapping_path=assets/'class_images.json'
    try:
        mapping=json.loads(mapping_path.read_text(encoding='utf-8')) if mapping_path.exists() else {}
        filename=mapping.get(label,label+'.png')
        if not isinstance(filename,str) or Path(filename).name != filename or Path(filename).suffix.lower() not in ('.png','.gif'):
            raise ValueError('图片配置需为本目录PNG/GIF文件名')
        path=assets/filename
        if not path.is_file():
            canvas.create_text(w/2,h/2,text='类别 %s 的图片待补充\n请放置 assets/class_images/%s' % (display_label,filename),
                               width=w-50,justify='center',fill='#687b8b',tags=('image_placeholder',));return
        photo=tk.PhotoImage(master=canvas,file=str(path))
        factor=max(1,math.ceil(photo.width()/max(1,w-40)),math.ceil(photo.height()/max(1,h-90)))
        if factor>1:photo=photo.subsample(factor,factor)
        canvas.category_image=photo
        canvas.create_image(w/2,(h+20)/2,image=photo,tags=('class_image',))
        canvas.create_text(w/2,h-15,text='类别参考图片；不是本次输入数据拍摄的现场图像',fill='#526779',font=('Microsoft YaHei UI',9))
    except (OSError,ValueError,tk.TclError) as exc:
        canvas.create_text(w/2,h/2,text='类别图片无法加载：'+str(exc),width=w-50,fill='#b14422')
