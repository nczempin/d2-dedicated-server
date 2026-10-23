const std=@import("std");
// Same bounded type-0 hash enumeration as native_player_census.h, with Mac
// Room1+10 -> Room2+58 -> Level+1D0 independently qualified (not 1.12 offsets).
pub const Row=struct{pointer:u32,guid:u32,class:u32,mode:u32,raw_x:u32,raw_y:u32,area:u32,inventory:u32,inventory_status:u32,name:[16]u8,next:u32};
pub const Slice=struct{count:u32,rows:[32]Row};
fn rowAt(a:anytype,p:u32)?Row{
 if(p==0 or (a.read(p) orelse return null)!=0)return null;
 var r=Row{.pointer=p,.guid=a.read(p+0xc) orelse return null,.class=a.read(p+4) orelse return null,.mode=a.read(p+0x10) orelse return null,.raw_x=0,.raw_y=0,.area=0,.inventory=0,.inventory_status=0,.name=@splat(0),.next=a.read(p+0xe4) orelse return null};
 if(r.guid==0 or r.class>6 or r.mode>20)return null;
 if(r.mode!=0){
  const data=a.read(p+0x14) orelse return null;const path=a.read(p+0x2c) orelse return null;
  if(data==0 or path==0 or (a.read(path+0x30) orelse return null)!=p)return null;
  for(0..4)|i|std.mem.writeInt(u32,r.name[i*4..][0..4],a.read(data+@as(u32,@intCast(i*4))) orelse return null,.little);
  const end=std.mem.indexOfScalar(u8,&r.name,0) orelse return null;if(end<2 or end>15)return null;
  for(r.name[0..end])|c|if(!std.ascii.isAlphabetic(c) and c!='-' and c!='_')return null;
  r.raw_x=a.read(path) orelse return null;r.raw_y=a.read(path+4) orelse return null;
  const room=a.read(path+0x1c) orelse return null;if(room==0)return null;
  const ex=a.read(room+0x10) orelse return null;if(ex==0)return null;
  const level=a.read(ex+0x58) orelse return null;if(level==0)return null;
  r.area=a.read(level+0x1d0) orelse return null;
  if(r.raw_x>>16<=1 or r.raw_y>>16<=1 or r.area==0 or r.area>136)return null;
  const inv=a.read(p+0x60) orelse return null;
  if(inv==0)r.inventory_status=1 else if((a.read(inv) orelse return null)==0x01020304 and (a.read(inv+8) orelse return null)==p and (a.read(inv+0x24) orelse return null)==r.guid){r.inventory=inv;r.inventory_status=2;}
 }
 return r;
}
pub fn capture(a:anytype,game:u32,actor:u32)?Slice{
 if(game==0 or actor==0)return null;
 var heads:[128]u32=undefined;for(&heads,0..)|*h,i|h.*=a.read(game+0x1120+@as(u32,@intCast(i*4))) orelse return null;
 var out=Slice{.count=0,.rows=undefined};var saw=false;
 for(heads,0..)|head,bucket|{var p=head;while(p!=0){
  if(out.count>=32)return null;const row=rowAt(a,p) orelse return null;
  if(row.guid&127!=bucket)return null;for(out.rows[0..out.count])|seen|if(seen.pointer==row.pointer or seen.guid==row.guid)return null;
  out.rows[out.count]=row;out.count+=1;saw=saw or row.guid==actor;p=row.next;
 }}
 if(!saw)return null;
 for(heads,0..)|head,i|if((a.read(game+0x1120+@as(u32,@intCast(i*4))) orelse return null)!=head)return null;
 for(out.rows[0..out.count])|before|if(!std.meta.eql(before,rowAt(a,before.pointer) orelse return null))return null;
 return out;
}
const Fake=struct{
 foreign:bool=false,cycle:bool=false,changed:bool=false,reads:u32=0,
 pub fn read(s:*Fake,p:u32)?u32{
  if(p>=0x11120 and p<0x11320){if(p==0x11124){s.reads+=1;return if(s.changed and s.reads>1)0 else 0x20000;}return 0;}
  return switch(p){0x20000=>0,0x20004=>1,0x2000c=>if(s.foreign)2 else 1,0x20010=>1,0x20014=>0x30000,0x2002c=>0x40000,0x20060=>0x50000,0x200e4=>if(s.cycle)0x20000 else 0,
   0x30000=>0x6e6e6f44,0x30004=>0x00622d61,0x30008,0x3000c=>0,
   0x40000=>5153<<16,0x40004=>4228<<16,0x4001c=>0x60000,0x40030=>0x20000,
   0x50000=>0x01020304,0x50008=>0x20000,0x50024=>1,0x60010=>0x70000,0x70058=>0x80000,0x801d0=>1,else=>null};
 }
};
test "complete loaded native players retain actual identity position inventory"{
 var a=Fake{};const s=capture(&a,0x10000,1).?;try std.testing.expectEqual(@as(u32,1),s.count);try std.testing.expectEqual(@as(u32,1),s.rows[0].area);try std.testing.expectEqualStrings("Donna-b",std.mem.sliceTo(&s.rows[0].name,0));try std.testing.expectEqual(@as(u32,2),s.rows[0].inventory_status);
}
test "foreign bucket cyclic changed or absent actor refuses census"{
 var a=Fake{.foreign=true};try std.testing.expect(capture(&a,0x10000,1)==null);
 a=.{.cycle=true};try std.testing.expect(capture(&a,0x10000,1)==null);
 a=.{.changed=true};try std.testing.expect(capture(&a,0x10000,1)==null);
 a=.{};try std.testing.expect(capture(&a,0x10000,99)==null);
}
