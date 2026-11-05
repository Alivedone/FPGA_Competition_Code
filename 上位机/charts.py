"""Tk Canvas charts for already-computed input spectra and class probabilities."""
import json
from pathlib import Path

# Same parula(256) table used by the MATLAB plotter, with scaled CData indexing.
_PARULA = json.loads(Path(__file__).with_name('parula256.json').read_text(encoding='utf-8'))

def waterfall_color(fraction):
    index = min(255, max(0, int(max(0., min(1., fraction))*256)))
    return '#%02x%02x%02x' % tuple(_PARULA[index])


def draw_probabilities(canvas, result):
    canvas.delete('all')
    w, h = max(canvas.winfo_width(), 420), max(canvas.winfo_height(), 240)
    left, right, top, bottom = 58, w-20, 65, h-65
    title = '九类别概率（Softmax）' if result['semantics'] == 'logits' else '九类别概率'
    canvas.create_text(w/2, 23, text=title, fill='#143753', font=('Microsoft YaHei UI', 12, 'bold'))
    for tick in range(6):
        probability = tick/5
        y = bottom - probability*(bottom-top)
        canvas.create_line(left, y, right, y, fill='#e3eaf0')
        canvas.create_text(left-8, y, text='%d%%' % (probability*100), anchor='e')
    canvas.create_line(left, top, left, bottom, right, bottom, fill='#748596')
    labels, probabilities = result.get('display_labels', result['labels']), result['probabilities']
    slot = (right-left)/len(labels)
    for i, (label, probability) in enumerate(zip(labels, probabilities)):
        x = left+(i+.5)*slot
        y = bottom-probability*(bottom-top)
        canvas.create_rectangle(x-slot*.3, y, x+slot*.3, bottom,
                                fill='#168da0' if i == result['index'] else '#86acc9',
                                outline='', tags=('probability_bar',))
        canvas.create_text(x, max(top-12, y-12), text='%.1f%%' % (probability*100), font=('Segoe UI', 9))
        canvas.create_text(x, bottom+17, text=str(label), width=max(20,int(slot)-2), tags=('class_label',))
    canvas.create_text((left+right)/2, h-15, text='类别（model_info.labels）', fill='#526779')


def draw_waterfall(canvas, window):
    """Rows are the actual ten consecutive frames; columns are all 512 bins."""
    canvas.delete('all')
    w, h = max(canvas.winfo_width(), 420), max(canvas.winfo_height(), 240)
    left, right, top, bottom = 58, w-88, 78, h-65
    frames, start = window['frames'], window['start_frame']
    values = [value for frame in frames for value in frame]
    lo, hi = min(values), max(values)
    canvas.create_text(w/2, 20, text='输入窗口瀑布图 · 帧 %d～%d' % (start,start+9),
                       fill='#143753', font=('Microsoft YaHei UI', 12, 'bold'))
    canvas.create_text(left, 48, text='帧编号（从下到上递增）', anchor='w', fill='#526779')
    width, height = (right-left)/512, (bottom-top)/10
    for row, frame in enumerate(frames):
        y0, y1 = bottom-(row+1)*height, bottom-row*height
        for column, value in enumerate(frame):
            color = waterfall_color((value-lo)/(hi-lo) if hi != lo else .5)
            canvas.create_rectangle(left+column*width, y0, left+(column+1)*width, y1,
                                    fill=color, outline='', tags=('waterfall_cell',))
        canvas.create_text(left-8,(y0+y1)/2,text=str(start+row),anchor='e',tags=('frame_label',))
    canvas.create_rectangle(left,top,right,bottom,outline='#748596')
    for index in (0,128,256,384,511):
        x = left+(index+.5)*width
        canvas.create_text(x,bottom+17,text=str(index))
    canvas.create_text((left+right)/2,h-15,text='频点编号（0～511）',fill='#526779')
    bar_left, bar_right = right+15, right+30
    for step in range(64):
        y0 = top+step/64*(bottom-top)
        y1 = top+(step+1)/64*(bottom-top)
        canvas.create_rectangle(bar_left,y0,bar_right,y1,fill=waterfall_color(1-(step+.5)/64),outline='')
    canvas.create_text(bar_right+5,top,text='%.3g' % hi,anchor='w')
    canvas.create_text(bar_right+5,bottom,text='%.3g' % lo,anchor='w')
    canvas.create_text(right+17,top-14,text='输入值',anchor='s',fill='#526779')
    canvas.create_text(right,bottom+38,text='每窗色标：标准化值',anchor='e',fill='#526779')


