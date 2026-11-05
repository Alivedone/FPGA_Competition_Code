// V2 control sequence, with logs on stderr; same cross-version hardware lock.
#pragma once
#include <icraft-xrt/core/session.h>
#include <icraft-xrt/dev/zg330_device.h>
#include <icraft-backends/zg330backend/zg330backend.h>
using namespace icraft::xrt;
using namespace icraft::xir;
constexpr size_t BYTES=10*512*4;
static void require(bool ok,const std::string& text){v3::check(ok,text);}
struct Bound {Tensor tensor;MemChunk chunk;uint64_t address,offset;};
#include <chrono>
#include <thread>
#include <memory>
#ifdef __linux__
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#endif
struct Lock {
#ifdef __linux__
 int fd=-1;
 Lock(){fd=open("/run/lock/lss_hsrv2.lock",O_CREAT|O_RDWR,0600);require(fd>=0,"Cannot create hardware lock");require(flock(fd,LOCK_EX|LOCK_NB)==0,"Another V2 process owns hardware");}
 ~Lock(){if(fd>=0)close(fd);}
#else
 Lock(){throw std::runtime_error("--run requires AArch64 Linux");}
#endif
};
class Bridge {
 RegRegion regs;
 uint32_t read(unsigned off)const{return static_cast<uint32_t>(regs.read(0xc0000+off,true));}
 void write(unsigned off,uint32_t v)const{regs.write(0xc0000+off,v,true);}
public:
 explicit Bridge(const Device& dev):regs(dev.getRegRegion("npu")){
  require(read(0)==0x4c535632,"LSV2 signature absent; install the integrated V2 BOOT");
  require(read(0x30)==0x10000,"Unknown bridge ABI");
  require(static_cast<uint32_t>(regs.read(0x8007c,true))==0x4c534332,"LSC2 control absent; install video-removed V2 BOOT");
  std::cerr<<"V2_SYSTEM_CTRL signature=LSC2 revision=video_removed"<<std::endl;
  require((read(8)&9)==8,"DDR not ready or DMA busy; stop other apps/reboot if needed");
 }
 void transfer(uint64_t ps,uint64_t dest){
  require(ps%64==0&&ps<=0x40000000ULL-BYTES,"PS DMA address outside aligned low-1GiB");
  require(dest%64==0&&dest<=0x100000000ULL-BYTES,"PL DDR address cannot fit V2 bus");
  require((read(8)&9)==8,"Bridge not ready/idle");
  auto seq=read(0xc),rejected=read(0x2c);
  write(0x10,static_cast<uint32_t>(ps));write(0x14,static_cast<uint32_t>(dest));write(0x18,10);
  std::cerr<<"V2_STAGE PL_DMA source=0x"<<std::hex<<ps<<" input=0x"<<dest<<std::dec<<" bytes="<<BYTES<<std::endl;
  write(4,1);
  auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(15);
  while(true){
   auto stat=read(8);
   if((stat&2)&&read(0xc)==static_cast<uint32_t>(seq+1)){
    require(!(stat&5)&&read(0x28)==0,"PL DMA/fence failure; code="+std::to_string(read(0x28)));
    require(read(0x1c)==BYTES&&read(0x20)==BYTES&&read(0x24)==BYTES,"Incomplete DMA/write/fence byte counts");
    require(read(0x2c)==rejected,"Control command rejected");return;
   }
   if(std::chrono::steady_clock::now()>deadline){
    // Do not destruct runtime buffers while a bus transaction may still be live.
    std::cerr<<"V2_FATAL_TIMEOUT reboot board before any further hardware use; no forward executed"<<std::endl;
    throw v3::HardwareFault("PL DMA timeout; reboot before further hardware use");
   }
   std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
 }
};
