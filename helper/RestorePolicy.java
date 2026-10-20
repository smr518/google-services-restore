import android.os.IBinder;
import android.os.Parcel;
import java.lang.reflect.Method;

/** Network policy adapter restricted to the two Google packages, for this build only. */
public class RestorePolicy {
  static Class<?> cls(String name) throws Exception {
    return (Class<?>)Class.class.getDeclaredMethod("forName",String.class).invoke(null,name);
  }
  static Method method(Class<?> c,String name,Class<?>... types) throws Exception {
    return (Method)Class.class.getDeclaredMethod("getDeclaredMethod",String.class,Class[].class)
      .invoke(c,new Object[]{name,types});
  }
  static IBinder service(String name) throws Exception {
    return (IBinder)method(cls("android.os.ServiceManager"),"getService",String.class).invoke(null,name);
  }
  static int uid(String pkg) throws Exception {
    if(!pkg.equals("com.google.android.gms") && !pkg.equals("com.android.vending")) throw new Exception("Package rejected");
    Class<?> apiClass=cls("android.content.pm.IPackageManager");
    Object api=method(cls("android.content.pm.IPackageManager$Stub"),"asInterface",IBinder.class).invoke(null,service("package"));
    int uid=(Integer)method(apiClass,"getPackageUid",String.class,long.class,int.class).invoke(api,pkg,0L,0);
    if(uid<10000 || uid>=20000) throw new Exception("Unexpected user or UID");
    return uid;
  }
  static boolean query(IBinder binder,int uid) throws Exception {
    Parcel d=Parcel.obtain(),r=Parcel.obtain();
    try {d.writeInt(uid);d.writeInt(-1);if(!binder.transact(1003,d,r,0))throw new Exception("Unsupported query");r.readException();return r.readBoolean();}
    finally {d.recycle();r.recycle();}
  }
  public static void main(String[] args) throws Exception {
    if(args.length!=2)throw new Exception("action and package required");
    String action=args[0],pkg=args[1]; int uid=uid(pkg); IBinder binder=service("netpolicy");
    boolean before=query(binder,uid);
    if(action.equals("query")){System.out.println("uid="+uid+" restricted="+before);return;}
    if(!action.equals("allow") && !action.equals("block"))throw new Exception("Action rejected");
    Parcel d=Parcel.obtain(),r=Parcel.obtain();
    try {d.writeInt(1);d.writeIntArray(new int[]{uid});d.writeIntArray(new int[]{action.equals("allow")?1:2});
      if(!binder.transact(1002,d,r,0))throw new Exception("Unsupported update");r.readException();if(!r.readBoolean())throw new Exception("Update rejected");}
    finally {d.recycle();r.recycle();}
    boolean after=query(binder,uid);if(after!=action.equals("block"))throw new Exception("Policy did not apply");
    System.out.println("uid="+uid+" restricted="+after);
  }
}
