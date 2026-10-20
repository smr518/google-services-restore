package com.smr.googlerestore;

import android.app.*;
import android.os.*;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.content.Intent;
import android.net.Uri;
import android.widget.*;
import android.view.*;
import java.io.*;
import java.security.MessageDigest;
import java.util.concurrent.*;

public class MainActivity extends Activity {
  private final ExecutorService work=Executors.newSingleThreadExecutor();
  private final Handler ui=new Handler(Looper.getMainLooper());
  private TextView state,log;
  private Button restore,check,repair,undo;
  private volatile boolean busy;
  private volatile boolean dead;
  private int dp(int n){return (int)(getResources().getDisplayMetrics().density*n);}
  private TextView text(String s,int size,int color){TextView t=new TextView(this);t.setText(s);t.setTextSize(size);t.setTextColor(color);return t;}
  private GradientDrawable card(int color){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(18));return d;}
  private void append(String s){ui.post(()->{if(!dead){log.append(s+"\n");}});}
  private void setState(String s){ui.post(()->{if(!dead)state.setText(s);});}
  private void setBusy(boolean b){busy=b;ui.post(()->{if(!dead){restore.setEnabled(!b);check.setEnabled(!b);repair.setEnabled(!b);undo.setEnabled(!b);}});}
  private Button button(LinearLayout parent,String title,boolean primary){
    Button b=new Button(this);b.setText(title);b.setAllCaps(false);b.setTextSize(16);b.setTextColor(primary?Color.WHITE:Color.rgb(22,80,65));
    b.setBackground(card(primary?Color.rgb(22,107,84):Color.rgb(226,237,231)));
    LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,dp(54));lp.topMargin=dp(12);parent.addView(b,lp);return b;
  }
  @Override public void onCreate(Bundle saved){super.onCreate(saved);
    getWindow().setStatusBarColor(Color.rgb(246,248,244));getWindow().setNavigationBarColor(Color.rgb(246,248,244));
    getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    ScrollView scroll=new ScrollView(this);scroll.setBackgroundColor(Color.rgb(246,248,244));
    LinearLayout body=new LinearLayout(this);body.setOrientation(1);body.setPadding(dp(24),dp(28),dp(24),dp(32));scroll.addView(body);setContentView(scroll);
    TextView badge=text("LSA · Android 14",13,Color.rgb(22,107,84));body.addView(badge);
    TextView title=text("谷歌服务恢复",30,Color.rgb(22,36,30));title.setTypeface(null,Typeface.BOLD);title.setPadding(0,dp(10),0,dp(12));body.addView(title);
    TextView intro=text("重启并重新获取 Root 后，手动恢复这台手机的谷歌组件。",16,Color.rgb(79,93,84));body.addView(intro);
    state=text("尚未检查。请先在 KernelSU 中允许本 App 获取 Root。",16,Color.rgb(22,64,49));state.setPadding(dp(18),dp(18),dp(18),dp(18));state.setBackground(card(Color.rgb(229,239,232)));
    LinearLayout.LayoutParams sp=new LinearLayout.LayoutParams(-1,-2);sp.topMargin=dp(22);sp.bottomMargin=dp(8);body.addView(state,sp);
    restore=button(body,"一键恢复",true);check=button(body,"检查状态",false);repair=button(body,"仅修复联网与下载",false);
    Button store=button(body,"打开 Play 商店",false);undo=button(body,"撤销本 App 的更改",false);
    TextView note=text("首次准备约需 1.5 GB 可用存储。恢复时可能短暂黑屏、关闭应用；不会自动提权或整机重启。只适配已验证的 LSA-AN00 / 8.0.0.221。",13,Color.rgb(92,101,94));note.setPadding(0,dp(20),0,dp(18));body.addView(note);
    log=text("",12,Color.rgb(74,84,78));log.setTextIsSelectable(true);log.setTypeface(Typeface.MONOSPACE);body.addView(log);
    check.setOnClickListener(v->execute("status"));repair.setOnClickListener(v->execute("repair"));
    restore.setOnClickListener(v->new AlertDialog.Builder(this).setTitle("恢复谷歌服务")
      .setMessage("请保存未完成的工作。若组件尚未挂载，会重启 Android 服务并关闭当前 App，约 1–3 分钟后重新打开查看结果；已有组件则只修复配置。不会整机重启，但异常时仍可能需要人工重启，临时 Root 可能丢失。")
      .setNegativeButton("取消",null).setPositiveButton("已保存，开始恢复",(d,w)->execute("restore")).show());
    undo.setOnClickListener(v->new AlertDialog.Builder(this).setTitle("撤销本 App 的更改")
      .setMessage("只撤销本 App 添加的配置和挂载，不删除账号、应用或暂存安装包。撤销挂载会重启 Android 服务。以前由电脑创建的挂载不会移除。请先保存工作。")
      .setNegativeButton("取消",null).setPositiveButton("撤销",(d,w)->execute("undo")).show());
    store.setOnClickListener(v->{try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse("market://details?id=com.google.android.youtube")).setPackage("com.android.vending"));}catch(Exception e){setState("尚未找到 Play 商店，请先恢复部署。");}});
  }
  private static String quote(String s){return "'"+s.replace("'","'\\''")+"'";}
  private static String guard(){return "L=$B/lock-$(cat /proc/sys/kernel/random/boot_id); "
    +"if [ -d \"$L\" ]; then P=$(cat \"$L/pid\" 2>/dev/null || true); case \"$P\" in ''|*[!0-9]*) exit 2;; esac; "
    +"if kill -0 \"$P\" 2>/dev/null; then exit 2; fi; rm -f \"$L/pid\"; rmdir \"$L\" || exit 2; fi; "
    +"mkdir \"$L\" || exit 2; echo $$ > \"$L/pid\"; trap 'rm -f \"$L/pid\"; rmdir \"$L\"' EXIT; ";}
  private String root(String command,int seconds) throws Exception {
    java.lang.Process p=new ProcessBuilder("/system/bin/sh","-c","exec /system/bin/su -M -c "+quote(command)).redirectErrorStream(true).start();
    ByteArrayOutputStream bytes=new ByteArrayOutputStream();
    Thread reader=new Thread(()->{try(InputStream in=p.getInputStream()){byte[] b=new byte[4096];int n;while((n=in.read(b))!=-1){synchronized(bytes){if(bytes.size()<65536)bytes.write(b,0,n);}}}catch(IOException ignored){}});
    reader.start();
    if(!p.waitFor(seconds,TimeUnit.SECONDS)){p.destroy();throw new IOException("Root 请求或命令超时；请检查 KernelSU 授权。未自动再次执行。");}
    reader.join(2000);String result; synchronized(bytes){result=bytes.toString("UTF-8");}
    if(p.exitValue()!=0)throw new IOException("命令未完成（"+p.exitValue()+"）："+result);
    return result.trim();
  }
  private File asset(String name,String expected) throws Exception {
    File dir=new File(getFilesDir(),"restore");if(!dir.exists()&&!dir.mkdirs())throw new IOException("无法创建准备目录");
    File f=new File(dir,name);if(f.exists()&&hash(f).equals(expected))return f;
    File temp=new File(dir,name+".tmp");
    try(InputStream in=getAssets().open(name);OutputStream out=new FileOutputStream(temp)){
      byte[] b=new byte[1024*1024];int n;long total=0;while((n=in.read(b))!=-1){out.write(b,0,n);total+=n;if(total%(32*1024*1024)<n)setState("正在准备内置文件："+(total/1024/1024)+" MB");}
    }
    if(!hash(temp).equals(expected))throw new IOException("内置文件校验失败："+name);
    if(!temp.renameTo(f))throw new IOException("保存内置文件失败");return f;
  }
  private String hash(File f) throws Exception {
    MessageDigest md=MessageDigest.getInstance("SHA-256");try(InputStream in=new FileInputStream(f)){byte[] b=new byte[1024*1024];int n;while((n=in.read(b))!=-1)md.update(b,0,n);}
    StringBuilder s=new StringBuilder();for(byte b:md.digest())s.append(String.format("%02x",b&255));return s.toString();
  }
  private void prepare(boolean payload) throws Exception {
    String id=root("id -u",35);if(!id.equals("0"))throw new IOException("未获得 Root，请先完成提权并在 KernelSU 授权。");
    File script=asset("restore.sh",AssetHashes.SCRIPT),control=asset("control.jar",AssetHashes.CONTROL);
    String base="/data/adb/google-restore";
    String setup="set -eu; B="+base+"; mkdir -p \"$B\"; chown 0:0 \"$B\"; chmod 700 \"$B\"; "
      +guard()
      +"cp "+quote(script.getAbsolutePath())+" \"$B/restore.sh\"; cp "+quote(control.getAbsolutePath())+" \"$B/control.jar\"; chmod 600 \"$B/restore.sh\" \"$B/control.jar\"";
    root(setup,20);
    if(payload){
      setState("正在核验安装包；已有缓存时会跳过解压。");
      String version=AssetHashes.PAYLOAD.substring(0,16);
      if(!root("test -f "+base+"/payload."+version+"/.ready && echo ready || echo missing",10).equals("ready")){
        File zip=asset("payload.zip",AssetHashes.PAYLOAD),sums=asset("payload.sha256",AssetHashes.SUMS);
        String p=base+"/payload."+version;
        root("set -eu; B="+base+"; "+guard()
          +"mkdir -p "+quote(p)+"; /data/adb/ksu/bin/busybox unzip -oq "+quote(zip.getAbsolutePath())+" -d "+quote(p)+"; "
          +"cp "+quote(sums.getAbsolutePath())+" \"$B/payload.sha256\"; cd "+quote(p)+"; /data/adb/ksu/bin/busybox sha256sum -c \"$B/payload.sha256\" >/dev/null; touch .ready",180);
      }
      File sums=asset("payload.sha256",AssetHashes.SUMS);
      root("set -eu; cp "+quote(sums.getAbsolutePath())+" "+base+"/payload.sha256; ln -sfn payload."+version+" "+base+"/payload",20);
    }
  }
  private void execute(String action){
    if(busy)return;setBusy(true);setState("正在请求 Root，请留意授权提示。");
    work.execute(()->{try{
      prepare(action.equals("restore"));
      if(action.equals("status")){String s=root("sh /data/adb/google-restore/restore.sh status",25);setState(s);append(s);return;}
      if(action.equals("restore")){String s=root("sh /data/adb/google-restore/restore.sh check",45);append(s);}
      String start="printf '操作排队中\\n' > /data/adb/google-restore/status; /data/adb/ksu/bin/busybox nohup /data/adb/ksu/bin/busybox setsid sh /data/adb/google-restore/restore.sh "+action
        +" > /data/adb/google-restore/operation.log 2>&1 < /dev/null &";
      root(start,15);setState("操作已启动；若界面暂时关闭，请稍后重新打开检查状态。");
      for(int i=0;i<120&&!dead;i++){
        Thread.sleep(2000);String s=root("cat /data/adb/google-restore/status 2>/dev/null; tail -n 8 /data/adb/google-restore/operation.log",15);setState(s);
        if(s.contains("恢复完成；")||s.contains("现有组件已恢复配置")||s.contains("配置已恢复；")||s.contains("更改已撤销")||s.contains("失败")||s.contains("停止操作")||s.contains("不足")){append(s);break;}
      }
    }catch(Exception e){setState("未完成："+e.getMessage());append(e.toString());}finally{setBusy(false);}});
  }
  @Override protected void onDestroy(){dead=true;ui.removeCallbacksAndMessages(null);work.shutdown();super.onDestroy();}
}
