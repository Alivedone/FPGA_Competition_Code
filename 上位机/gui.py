"""LSS_HSR目标识别 desktop client. Python 3.10+, standard library only."""
import json
import os
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from controller import Controller, inspect_files
from results import metadata, read_result, read_input_window, read_track_window
from class_labels import task_truth_name, truth_from_metadata
from input_data import inspect_source

ROOT = Path(__file__).resolve().parent


class App:
    def __init__(self, root):
        self.root, self.control = root, Controller()
        self.connected = self.busy = self.stopping = False
        self.files, self.results = [], {}
        self.last_output = ROOT / 'output' / 'gui_results'
        self.detail = None
        self.active_path = None
        self.inputs, self.edit_buttons = [], []
        for key, value in dict(host='192.168.1.11', port='5001', timeout='120', start='0',
                               out=str(self.last_output), status='未连接：请先启动板卡 TCP 服务',
                               model='模型：尚未读取', preview='请选择标准化 BIN 文件').items():
            setattr(self, key, tk.StringVar(value=value))
        root.title('LSS_HSR目标识别')
        root.geometry('1240x800'); root.minsize(1050, 780)
        style = ttk.Style(root); style.theme_use('clam')
        style.configure('.', font=('Microsoft YaHei UI', 10))
        style.configure('Title.TLabel', font=('Microsoft YaHei UI', 21, 'bold'), foreground='#143753')
        style.configure('Treeview', rowheight=32)
        main = ttk.Frame(root, padding=18); main.pack(fill='both', expand=True)
        ttk.Label(main, text='LSS_HSR目标识别', style='Title.TLabel').pack(anchor='w')
        ttk.Label(main, text='数据传输 · 硬件推理 · 结果验证').pack(anchor='w', pady=(0, 10))
        net = ttk.LabelFrame(main, text='板卡连接', padding=10); net.pack(fill='x')
        for label, variable, width in [('板卡 IP', self.host, 18), ('端口', self.port, 7), ('超时 / 秒', self.timeout, 7)]:
            ttk.Label(net, text=label).pack(side='left', padx=(0, 5))
            entry = ttk.Entry(net, textvariable=variable, width=width); entry.pack(side='left', padx=(0, 12)); self.inputs.append(entry)
        self.connect_button = ttk.Button(net, text='连接并读取模型', command=self.connect); self.connect_button.pack(side='left')
        self.disconnect_button = ttk.Button(net, text='断开连接', command=self.disconnect); self.disconnect_button.pack(side='left', padx=8)
        body = ttk.Panedwindow(main, orient='horizontal'); body.pack(fill='both', expand=True)
        left = ttk.LabelFrame(body, text='待发送数据', padding=10)
        right = ttk.Frame(body); body.add(left, weight=2); body.add(right, weight=3)
        buttons = ttk.Frame(left); buttons.pack(fill='x')
        for text, action in [('添加 BIN', self.add_files), ('移除选中', self.remove_files), ('清空', self.clear_files)]:
            b = ttk.Button(buttons, text=text, command=action); b.pack(side='left', padx=(0, 5)); self.edit_buttons.append(b)
        listing = ttk.Frame(left); listing.pack(fill='both', expand=True, pady=10)
        self.listbox = tk.Listbox(listing, selectmode='extended', exportselection=False, height=3, font=('Microsoft YaHei UI', 10))
        scroll = ttk.Scrollbar(listing, orient='vertical', command=self.listbox.yview)
        self.listbox.configure(yscrollcommand=scroll.set); scroll.pack(side='right', fill='y'); self.listbox.pack(fill='both', expand=True)
        horizontal = ttk.Scrollbar(left, orient='horizontal', command=self.listbox.xview); horizontal.pack(fill='x')
        self.listbox.configure(xscrollcommand=horizontal.set)
        params = ttk.Frame(left); params.pack(fill='x', pady=10)
        ttk.Label(params, text='起始帧（从 0 开始）').pack(side='left')
        e = ttk.Entry(params, textvariable=self.start, width=8); e.pack(side='left', padx=8); self.edit_buttons.append(e)
        self.fixed_note = ttk.Label(left, text='每个文件从起始帧取连续10帧进行推理。\n支持512点频谱 / new_data组合BIN＋JSON；仅上传频谱。')
        self.fixed_note.pack(anchor='w', pady=10)
        ttk.Label(left, textvariable=self.preview, wraplength=400, foreground='#326080').pack(anchor='w')
        ttk.Label(left, text='PC 结果保存目录').pack(anchor='w', pady=(12, 4))
        location = ttk.Frame(left); location.pack(fill='x')
        e = ttk.Entry(location, textvariable=self.out); e.pack(side='left', fill='x', expand=True); self.edit_buttons.append(e)
        b = ttk.Button(location, text='浏览', command=self.choose_output); b.pack(side='left', padx=(5, 0)); self.edit_buttons.append(b)
        self.send_button = ttk.Button(left, text='按列表顺序发送并接收结果', command=self.send); self.send_button.pack(fill='x', pady=(12, 6))
        self.stop_button = ttk.Button(left, text='当前任务完成后停止板端服务', command=self.stop); self.stop_button.pack(fill='x')
        tabs = ttk.Notebook(right); tabs.pack(fill='both', expand=True)
        results_tab, log_tab = ttk.Frame(tabs, padding=8), ttk.Frame(tabs, padding=8)
        tabs.add(results_tab, text='任务结果'); tabs.add(log_tab, text='通信日志')
        self.table = ttk.Treeview(results_tab, columns=('number', 'file', 'truth', 'state'), show='headings', selectmode='browse')
        for key, title, width in [('number','数据编号',75), ('file','输入文件',240), ('truth','发送类别',90), ('state','任务状态',160)]:
            self.table.heading(key, text=title); self.table.column(key, width=width, minwidth=45, stretch=key in ('file','state'))
        vs = ttk.Scrollbar(results_tab, command=self.table.yview); vs.pack(side='right', fill='y')
        self.table.configure(yscrollcommand=vs.set); self.table.pack(fill='both', expand=True)
        self.table.tag_configure('failed', foreground='#bb3333')
        self.table.bind('<<TreeviewSelect>>', self.select_result)
        self.table.bind('<Double-1>', lambda _: self.open_detail())
        actions = ttk.Frame(right); actions.pack(fill='x', pady=8)
        self.detail_button = ttk.Button(actions, text='查看识别详情', command=self.open_detail); self.detail_button.pack(side='left')
        ttk.Button(actions, text='加载历史任务', command=self.load_result).pack(side='left', padx=5)
        ttk.Button(actions, text='加载离线示例', command=self.load_examples).pack(side='left', padx=(0,5))
        ttk.Button(actions, text='打开结果目录', command=self.open_output).pack(side='left')
        self.clear_results_button = ttk.Button(actions, text='清空任务结果', command=self.clear_results)
        self.clear_results_button.pack(side='left', padx=(5, 0))
        self.selection_note = tk.StringVar(value='选择任务后查看识别详情；结果自动保存在 PC。')
        ttk.Label(right, textvariable=self.selection_note, wraplength=620).pack(anchor='w')
        self.log = tk.Text(log_tab, wrap='word', state='disabled', font=('Consolas', 10))
        ls = ttk.Scrollbar(log_tab, command=self.log.yview); ls.pack(side='right', fill='y')
        self.log.configure(yscrollcommand=ls.set); self.log.pack(fill='both', expand=True)
        ttk.Label(main, textvariable=self.status, foreground='#126881', wraplength=1150).pack(anchor='w', pady=(12, 0))
        self.start.trace_add('write', lambda *_: self.update_preview())
        root.protocol('WM_DELETE_WINDOW', self.close)
        self.refresh(); root.after(80, self.poll)

    def add_files(self):
        initial = ROOT.parent / 'dataset'
        if not initial.exists(): initial = ROOT.parent / 'dataset' / 'data_stand'
        for p in filedialog.askopenfilenames(title='添加已标准化 BIN', initialdir=str(initial if initial.exists() else ROOT), filetypes=[('BIN 文件','*.bin')]):
            self.files.append(p); self.listbox.insert('end', p)
        self.update_preview()

    def update_preview(self):
        try:
            rows = inspect_files(self.files, *self.parameters())
            labels = []
            for filename in self.files:
                truth = truth_from_metadata(inspect_source(filename)['metadata'])
                labels.append(truth['class_name'] if truth else '未知')
            shown = ' / '.join(labels[:8]) + (' / …' if len(labels) > 8 else '')
            self.preview.set('共 %d 个文件 / %d 个窗口；发送类别：%s' % (len(rows), sum(r['windows'] for r in rows), shown))
        except (ValueError, OSError) as exc:
            self.preview.set('请检查参数：%s。起始帧最大为文件帧数减 10。' % exc)

    def record_result(self, path, source, report):
        path = Path(path)
        try:
            info, names = metadata(path)
            if names:
                read_result(path, names[-1])
        except (ValueError, OSError, KeyError, TypeError) as exc:
            self.log_line('历史结果读取失败：' + str(exc))
        try:
            truth = task_truth_name(path)
        except (ValueError, OSError, KeyError, TypeError) as exc:
            truth = '标签无效'; self.log_line('发送类别读取失败：' + str(exc))
        passed = report.get('passed', False)
        state = ('成功 · 硬件' if report.get('physical_execution') else '成功 · 参考') if passed else '失败 / 未完成'
        if report.get('offline_validation'):
            state = '图片映射演示' if report.get('synthetic_output') else '离线PC真实结果'
        source_label=Path(source).name
        if report.get('offline_validation') and report.get('source_group'):
            source_label=report['source_group']+' / '+source_label
        number = 'R%04d' % (len(self.table.get_children()) + 1)
        iid = self.table.insert('', 0, values=(number, source_label, truth, state), tags=() if passed else ('failed',))
        self.results[iid] = path; self.table.selection_set(iid); self.table.see(iid)
        self.select_result()
        return iid

    def poll(self):
        while not self.control.events.empty():
            event = self.control.events.get_nowait(); kind = event['kind']
            self.log_line(json.dumps(event, ensure_ascii=False))
            if kind == 'connected':
                self.connected, self.busy = True, False
                info = event['info']
                self.model.set('模型：%s | %s | %s | 输出 %s' % (info.get('model_id','?'), info['model_kind'], '真实硬件' if info['physical_execution'] else '参考模式（未调用 NPU）', info['output']['shape']))
                self.status.set('READY：可以发送任务')
            elif kind == 'task_start':
                self.status.set('任务 %d/%d：%s，%d 帧 → %d 个窗口' % (event['index'], event['total'], Path(event['path']).name, event['frames'], event['windows']))
            elif kind == 'protocol' and event['header']['type'] == 'RESULT':
                self.status.set('收到窗口 %d，正在校验并保存' % event['header']['window_index'])
            elif kind in ('result','task_failed'):
                self.record_result(event['path'], event['source'], event['report'])
                if kind == 'task_failed': self.status.set(event['message'])
            elif kind == 'batch_done':
                self.busy = False
                if not self.stopping: self.status.set('本轮结束：成功 %d，失败 %d；服务 READY，可继续发送。选择任务可查看识别详情。' % (event.get('succeeded',0), event.get('failed',0)))
            elif kind in ('error','stopped','disconnected'):
                self.connected = self.busy = self.stopping = False
                self.model.set('模型：连接已断开')
                self.status.set({'error':'连接或任务失败，请检查通信日志和板端状态', 'stopped':'STOPPED：板端服务已停止；再次测试前请重新启动服务', 'disconnected':'连接已断开；板端服务未停止'}[kind])
                if kind == 'error': messagebox.showerror('操作失败', event['message'] + '\n已断开连接；部分任务证据可能保留在结果目录。')
            self.refresh()
        self.root.after(80, self.poll)

    def select_result(self, _=None):
        selection = self.table.selection()
        self.detail_button.configure(state='normal' if selection else 'disabled')
        if selection: self.selection_note.set('已选择：%s\n点击“查看识别详情”查看该任务的轨迹及识别结果。' % self.results[selection[0]].name)
        else: self.selection_note.set('选择任务后查看识别详情；结果文件保存在 PC。')
        self.clear_results_button.configure(state='normal' if self.results and not (self.busy or self.stopping) else 'disabled')

    def clear_results(self):
        if self.busy or self.stopping:
            return
        self.active_path = None
        if self.detail is not None and self.detail.winfo_exists():
            self.detail.destroy()
        self.detail = None
        rows = self.table.get_children()
        if rows:
            self.table.delete(*rows)
        self.results.clear()
        self.select_result()
        self.selection_note.set('已清空界面任务结果；磁盘结果和通信日志保留，可加载历史任务查看。')
        self.refresh()

    def load_result(self):
        p = filedialog.askdirectory(title='选择包含 task.json / events.jsonl 的任务目录')
        if not p: return
        try:
            path = Path(p); task = json.loads((path/'task.json').read_text(encoding='utf-8'))
            report_path = path/'client_report.json'
            report = json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {}
            metadata(path)
            self.record_result(path, task.get('source_path', path.name), report)
        except (OSError, ValueError, KeyError, TypeError) as exc: messagebox.showerror('历史任务', str(exc))

    def open_detail(self):
        selection = self.table.selection()
        if not selection: return
        self.show_result(self.results[selection[0]])

    def load_examples(self):
        try:
            base=ROOT/'examples'
            index=json.loads((base/'index.json').read_text(encoding='utf-8'))
            for item in index['tasks']:
                path=(base/item['path']).resolve()
                if not path.is_relative_to(base.resolve()):raise ValueError('示例路径无效')
                task=json.loads((path/'task.json').read_text(encoding='utf-8'))
                report=json.loads((path/'client_report.json').read_text(encoding='utf-8'))
                metadata(path);self.record_result(path,task['source_path'],report)
            self.status.set('已加载离线示例：PC真实ResNet结果和人为指定类别的图片演示；均未调用板卡NPU。选择任务后查看详情。')
        except (OSError,ValueError,KeyError,TypeError) as exc:messagebox.showerror('离线示例',str(exc))

    def show_result(self, path):
        if self.detail is None or not self.detail.winfo_exists():
            self.detail = tk.Toplevel(self.root); self.detail.title('LSS_HSR目标识别 · 轨迹识别详情')
            self.detail.geometry('1180x850'); self.detail.minsize(1000, 700)
            frame = ttk.Frame(self.detail, padding=16); frame.pack(fill='both', expand=True)
            self.detail_title = tk.StringVar(); self.metric = tk.StringVar(); self.detail_state = tk.StringVar()
            self.window_choice = ttk.Combobox(frame, state='readonly')
            self.window_choice.bind('<<ComboboxSelected>>', lambda _: self.draw_selected())
            self.track_x_step=tk.StringVar(value='0');self.track_y_step=tk.StringVar(value='0')
            self.category_plot = tk.Canvas(frame, background='white', height=140, highlightthickness=0)
            self.category_plot.pack(fill='x', pady=(0, 8))
            self.track_plot = tk.Canvas(frame, background='white', highlightthickness=0)
            self.track_plot.pack(fill='both', expand=True)
            self.track_plot.bind('<Configure>', lambda _: self.draw_selected())
            self.category_plot.bind('<Configure>', lambda _: self.draw_selected())
            self.track_note = tk.StringVar()
        self.active_path = Path(path)
        self.track_plot.delete('all'); self.category_plot.delete('all'); self.category_plot.category_image=None
        self.track_note.set(''); self.window_choice.set(''); self.window_choice['values']=()
        self.metric.set('此任务无可用结果。'); self.detail_title.set(str(path))
        try:
            report_path=self.active_path/'client_report.json'
            report=json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {}
            self.detail_state.set('任务已完成；显示所选10帧窗口轨迹。' if report.get('passed') else '任务失败或未完成确认；仅显示校验通过的窗口。')
            if report.get('offline_validation'):
                self.detail_state.set('图片映射演示：人为指定类别，仅检查图片和轨迹显示；不是模型推理结果。' if report.get('synthetic_output') else '离线PC真实ResNet结果：Icraft HostBackend计算，未上传板卡、未执行NPU。')
            _,names=metadata(path); self.window_choice['values']=names
            if names:self.window_choice.set(names[0])
            self.draw_selected()
        except (OSError,ValueError,KeyError,TypeError) as exc:
            self.metric.set('无法读取结果：'+str(exc))
            self.draw_selected()
        self.detail.deiconify();self.detail.lift()

    def draw_selected(self):
        if self.detail is None or not self.detail.winfo_exists():
            return
        self.track_plot.delete('all');self.category_plot.delete('all');self.category_plot.category_image=None
        self.track_note.set('')
        from detail_charts import draw_class_gallery, draw_track
        truth = None
        if self.active_path:
            try:
                truth = task_truth_name(self.active_path)
            except (OSError,ValueError,KeyError,TypeError) as exc:
                self.log_line('发送类别读取失败：'+str(exc))
        draw_class_gallery(self.category_plot, truth, ROOT/'assets'/'class_images')
        if not self.active_path or not self.window_choice.get():
            self.track_plot.create_text(30,30,text='此任务没有有效返回结果，请查看通信日志。',anchor='nw',tags=('track_error',));return
        try:
            result=read_result(self.active_path,self.window_choice.get());self.metric.set(result['metric'])
            try:
                track=read_track_window(self.active_path,self.window_choice.get())
                draw_track(self.track_plot,track,float(self.track_x_step.get()),float(self.track_y_step.get()))
                self.track_note.set('轨迹与推理输入使用同一文件、同一起始帧及10帧窗口；只上传频谱，轨迹保存在PC。图中X/Y以窗口起点为零点，单位m，自动放大选段；未标定地理朝向。' if track else '旧任务只有频谱，没有已归档的轨迹；不能按文件名猜测补配。')
            except (OSError,ValueError,KeyError,TypeError) as exc:
                self.track_plot.delete('all')
                self.track_plot.create_text(30,30,text='轨迹不可用：'+str(exc),anchor='nw',width=800,fill='#b14422',tags=('track_error',))
                self.track_note.set('绘图参数或轨迹关联校验未通过；分类结果已独立校验。')
        except (OSError,ValueError,KeyError,TypeError) as exc:
            self.track_plot.delete('all')
            self.track_plot.create_text(30,30,text='无法显示：'+str(exc),anchor='nw',width=800,fill='#b14422',tags=('track_error',))
            self.metric.set('无法显示：'+str(exc))


    def auto_track_scale(self):
        self.track_x_step.set('0');self.track_y_step.set('0');self.draw_selected()

    def log_line(self, text):
        line = datetime.now().strftime('%H:%M:%S') + '  ' + text + '\n'
        self.log.configure(state='normal'); self.log.insert('end', line); self.log.see('end'); self.log.configure(state='disabled')

    def refresh(self):
        locked = self.busy or self.stopping
        for widget in self.edit_buttons:
            widget.configure(state='disabled' if locked else 'normal')
        for widget in self.inputs:
            widget.configure(state='disabled' if self.connected or locked else 'normal')
        self.connect_button.configure(state='disabled' if self.connected or locked else 'normal')
        self.disconnect_button.configure(state='normal' if self.connected and not locked else 'disabled')
        self.send_button.configure(state='normal' if self.connected and not locked else 'disabled')
        self.stop_button.configure(state='normal' if self.connected and not self.stopping else 'disabled')
        self.clear_results_button.configure(state='normal' if self.results and not locked else 'disabled')

    def connect(self):
        try:
            port, timeout = int(self.port.get()), float(self.timeout.get())
            if not 1 <= port <= 65535 or not 1 <= timeout <= 3600 or not self.host.get().strip():
                raise ValueError('请输入有效的 IP、端口及超时')
            self.busy = True; self.status.set('正在连接并等待 READY…'); self.refresh()
            self.control.command('connect', host=self.host.get().strip(), port=port, timeout=timeout)
        except ValueError as exc:
            messagebox.showerror('连接参数', str(exc))

    def disconnect(self):
        self.busy = True; self.refresh(); self.control.command('disconnect')

    def remove_files(self):
        for i in reversed(self.listbox.curselection()):
            del self.files[i]; self.listbox.delete(i)
        self.update_preview()

    def clear_files(self):
        self.files.clear(); self.listbox.delete(0, 'end'); self.update_preview()

    def parameters(self):
        start = int(self.start.get())
        if start < 0:
            raise ValueError('起始帧必须为非负整数')
        return start, 1, 1

    def choose_output(self):
        p = filedialog.askdirectory(title='选择 PC 结果目录')
        if p: self.out.set(p)

    def send(self):
        try:
            start, count, step = self.parameters()
            inspect_files(self.files, start, count, step)
            if not self.out.get().strip(): raise ValueError('请选择结果目录')
            output = Path(self.out.get()).expanduser().resolve(); output.mkdir(parents=True, exist_ok=True)
            self.last_output = output; self.busy = True; self.refresh()
            self.status.set('校验输入并发送；请保留程序运行，结果将自动保存到 PC')
            self.control.command('send', files=list(self.files), start=start, count=count, step=step, output=str(output))
        except (ValueError, OSError) as exc:
            messagebox.showerror('发送参数', str(exc))

    def stop(self):
        self.stopping = True; self.status.set('已预约停止：完成当前任务后排空并退出；列表剩余文件不再发送')
        self.control.request_stop(); self.refresh()

    def open_output(self):
        self.last_output.mkdir(parents=True, exist_ok=True); os.startfile(str(self.last_output))

    def close(self):
        if self.busy or self.stopping:
            messagebox.showinfo('任务正在运行', '请等待任务结束，或点击“当前任务完成后停止服务”。运行中关闭会失去任务结果，当前界面保留运行。')
            return
        self.control.command('shutdown'); self.root.destroy()

if __name__ == '__main__':
    root = tk.Tk(); App(root); root.mainloop()
