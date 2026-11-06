# SCM changes deliberately leave account/password, dependencies and service ACL
# untouched. Never delete/recreate an existing registration during migration.
if (-not ('BackupServiceScm' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class BackupServiceScm {
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenSCManager(string m,string d,uint a);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenService(IntPtr s,string n,uint a);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool ChangeServiceConfig(IntPtr s,uint t,uint start,uint err,string image,string group,IntPtr tag,string deps,string user,string password,string display);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool QueryServiceConfig2(IntPtr s,uint level,IntPtr data,uint size,out uint needed);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool ChangeServiceConfig2(IntPtr s,uint level,IntPtr data);
  [DllImport("advapi32.dll")] static extern bool CloseServiceHandle(IntPtr s);
  [StructLayout(LayoutKind.Sequential)] struct Actions { public uint Reset; public IntPtr Reboot,Command; public uint Count; public IntPtr Items; }
  [StructLayout(LayoutKind.Sequential)] struct Action { public int Type; public uint Delay; }
  public class Recovery { public uint Reset; public string Reboot,Command; public int[] Types; public uint[] Delays; public bool NonCrash; }
  static void WithService(string name, System.Action<IntPtr> fn) {
    var scm=OpenSCManager(null,null,1); if(scm==IntPtr.Zero) throw new Win32Exception();
    try { var s=OpenService(scm,name,0x13); if(s==IntPtr.Zero) throw new Win32Exception();
      try { fn(s); } finally { CloseServiceHandle(s); }
    } finally { CloseServiceHandle(scm); }
  }
  public static void SetImage(string name,string image) {
    WithService(name,s=> { if(!ChangeServiceConfig(s,uint.MaxValue,uint.MaxValue,uint.MaxValue,image,null,IntPtr.Zero,null,null,null,null)) throw new Win32Exception(); });
  }
  public static Recovery GetRecovery(string name) {
    var result=new Recovery();
    WithService(name,s=> {
      uint size; QueryServiceConfig2(s,2,IntPtr.Zero,0,out size);
      var p=Marshal.AllocHGlobal((int)size);
      try {
        if(!QueryServiceConfig2(s,2,p,size,out size)) throw new Win32Exception();
        var a=(Actions)Marshal.PtrToStructure(p,typeof(Actions));
        result.Reset=a.Reset; result.Reboot=Marshal.PtrToStringUni(a.Reboot); result.Command=Marshal.PtrToStringUni(a.Command);
        result.Types=new int[a.Count]; result.Delays=new uint[a.Count];
        for(int i=0;i<a.Count;i++) { var v=(Action)Marshal.PtrToStructure(IntPtr.Add(a.Items,i*Marshal.SizeOf(typeof(Action))),typeof(Action)); result.Types[i]=v.Type; result.Delays[i]=v.Delay; }
      } finally { Marshal.FreeHGlobal(p); }
      p=Marshal.AllocHGlobal(4);
      try { if(!QueryServiceConfig2(s,4,p,4,out size)) throw new Win32Exception(); result.NonCrash=Marshal.ReadInt32(p)!=0; }
      finally { Marshal.FreeHGlobal(p); }
    }); return result;
  }
  public static void SetRecovery(string name,Recovery r) {
    WithService(name,s=> {
      var items=Marshal.AllocHGlobal(Math.Max(1,r.Types.Length)*Marshal.SizeOf(typeof(Action)));
      var p=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(Actions)));
      var reboot=Marshal.StringToHGlobalUni(r.Reboot ?? ""); var command=Marshal.StringToHGlobalUni(r.Command ?? "");
      try {
        for(int i=0;i<r.Types.Length;i++) Marshal.StructureToPtr(new Action{Type=r.Types[i],Delay=r.Delays[i]},IntPtr.Add(items,i*Marshal.SizeOf(typeof(Action))),false);
        Marshal.StructureToPtr(new Actions{Reset=r.Reset,Reboot=reboot,Command=command,Count=(uint)r.Types.Length,Items=items},p,false);
        if(!ChangeServiceConfig2(s,2,p)) throw new Win32Exception();
        Marshal.WriteInt32(p,r.NonCrash?1:0); if(!ChangeServiceConfig2(s,4,p)) throw new Win32Exception();
      } finally { Marshal.FreeHGlobal(items); Marshal.FreeHGlobal(p); Marshal.FreeHGlobal(reboot); Marshal.FreeHGlobal(command); }
    });
  }
}
'@
}

function Set-ServiceRecoverySnapshot([string]$Name, $Saved) {
    $recovery = New-Object BackupServiceScm+Recovery
    $recovery.Reset = $Saved.Reset
    $recovery.Reboot = $Saved.Reboot
    $recovery.Command = $Saved.Command
    $recovery.Types = [int[]]@($Saved.Types)
    $recovery.Delays = [uint32[]]@($Saved.Delays)
    $recovery.NonCrash = [bool]$Saved.NonCrash
    [BackupServiceScm]::SetRecovery($Name, $recovery)
}
