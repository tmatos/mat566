/*
 * Rotinas para mapeamento da memoria principal para o acesso por FPGA via PCIe
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/mman.h>

// PCI CONSTANTS
#define PCI_VENDOR_ID 0x1172
#define PCI_DEVICE_ID 0x0004
#define MMAP_SIZE 65536

// ADDRESS MAP (lido da aba 'Address Map' no QSYS)
#define PCI_OUTPORT 0Xc400 // 4 bytes amplo
#define PCI_INPORT 0Xc410  // 4 bytes amplo
#define PCI_MEMORY 0Xc000  // 1024 bytes amplo
//#define PCI_OUTPORT 0X0040 // 4 bytes amplo
//#define PCI_INPORT 0X0050  // 4 bytes amplo
//#define PCI_MEMORY 0X0000  // 64 bytes amplo

// AES VARS OFFSET
#define AES_KEY_OFFSET  0
#define AES_PLAINTEXT_OFFSET 16
#define AES_CIPHERTEXT_OFFSET 32

// MEUS OFFSETS (Tiago)
#define DATA_OFFSET  0
#define RESULT_OFFSET 512 // TODO: MUDAR para algo mais, checar viabilid.

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long u64;

// TIAGO!!!: vc tirou os inlines todos das funcoes pq nao tava linkando...


// finds PCI base address by vendor & device id    
int pci_read_base_address(int vendor, int device)
{
    FILE* f;
    int mem, dev, dum;
    char buf[0x1000];

    f = fopen("/proc/bus/pci/devices", "r");
    if (!f)
      return 0;

    while ( fgets(buf, sizeof(buf)-1, f) ) {
        if (sscanf(buf,"%x %x %x %x", &dum, &dev, &dum, &mem) != 4) {
          continue;
        }
        if ( dev == ((vendor<<16)|device) ) {
            fclose(f);
            return mem;
        }
    }
    fclose(f);
    return 0;
}

// ler n inteiros de um endereco
/*inline*/ void pci_mm_read(u32* dst, u32* devptr, int offset, int n){
  int i;
  for(i=0; i<n*4; i+=4)
    *(u32*)((u32)dst+i) = *(u32*)((u32)devptr+offset+i);
}

// escrever n inteiros para um endereco
/*inline*/ void pci_mm_write(u32* src, u32* devptr, int offset, int n){
  int i;
  for(i=0; i<n*4; i+=4)
    *(u32*)((u32)devptr+offset+i) = *(u32*)((u32)src+i);
}

// write to output PIO
/*inline*/ void pci_send_command(u32* ptr, u32 cmd){
  pci_mm_write(&cmd, ptr, PCI_OUTPORT, 1);

  // comementei abaixo, pois estou retornando para 0 depois (Tiago)
  //u32 c = 0;
  //pci_mm_write(&c, ptr, PCI_OUTPORT, 1);  // We don't want our command to repeat itself (if bus latches)
}

// read from input PIO
/*inline*/ u32 pci_get_status(u32* ptr){
    u32 r;
    pci_mm_read(&r, ptr, PCI_INPORT, 1);
    return r;
}

// run AES operation
/*inline*/ void pci_aes128(u32* ptr, u32* cipher, u32* key, u32* txt){
  // Write key and plaintext
  pci_mm_write(key, ptr, PCI_MEMORY+AES_KEY_OFFSET, 4);
  pci_mm_write(txt, ptr, PCI_MEMORY+AES_PLAINTEXT_OFFSET, 4);
  
  // Send start signal
  pci_send_command(ptr, 1);
  
  // Wait till it's ready
  // It's not always nessecary (if the reading delay is more than custom logic delay, the output is ready anyway)
  while(pci_get_status(ptr) != 1);

  
  pci_send_command(ptr, 0); // (Tiago)

  // Read ciphertext
  pci_mm_read(cipher, ptr, PCI_MEMORY+AES_CIPHERTEXT_OFFSET, 4);
}

static int fd;

// Getting the device pointer
u32* get_device() {

  size_t page_size = (size_t) sysconf(_SC_PAGESIZE); // DBG
  printf("PAGESIZE = %d\n", page_size);              // DBG

  fd = open("/dev/mem", O_RDWR|O_SYNC); // mandada para o static (Tiago)

  int pci_bar0 = pci_read_base_address(PCI_VENDOR_ID, PCI_DEVICE_ID);

  /*
  u32* ptr = mmap(0, 
                    MMAP_SIZE,
                    PROT_READ|PROT_WRITE,
                    MAP_SHARED,
                    fd,
                    pci_bar0);
  */

  u32* ptr = mmap((void*)0xb7700000, // 0xb7700000 eh dica
                  MMAP_SIZE,
                  PROT_READ|PROT_WRITE,
                  MAP_SHARED,
                  fd,
                  pci_bar0);
  
  if(ptr == MAP_FAILED) {
    perror("MMAP FAILED\n");
    exit(1);
  }
  else {
    printf("PCI BAR0 0x0000 = 0x%4x\n",  (u32) ptr);
  }

  return ptr;
}

//
//
void close_device(u32* ptr) {
    munmap(ptr, MMAP_SIZE);
    close(fd);
}

// mover dados para a memoria compartilhada
//
// ptr - ponteiro para o device de memoria
// data - ponteiro para os dados
// n - comprimento dos dados em numero de inteiros
void move(u32* ptr, u32* data, int n) {

  pci_mm_write(data, ptr, PCI_MEMORY+DATA_OFFSET, n);

  msync(ptr, MMAP_SIZE, MS_SYNC); //talvez precise usar isso
  
  // TODO: precisa de mais algo?
}

// ler dados da memoria compartilhada
// ptr - ponteiro para o device de memoria
// dest - ponteiro o local de destino dos dados lidos
// n - comprimento dos dados em numero de inteiros
void get(u32* ptr, u32* dest, int n) {
  
  pci_mm_read(dest, ptr, PCI_MEMORY+RESULT_OFFSET, n);

  // TODO: precisa de mais algo?
}

//
void executar(u32* ptr) {
  
  // Send start signal
  /////printf(">>> vai enviar start\n");
  pci_send_command(ptr, 1);
  msync(ptr, MMAP_SIZE, MS_SYNC); //talvez precise usar isso
  /////printf(">>> enviou start\n");
  
  // Wait till it's ready
  // It's not always nessecary (if the reading delay is more than custom logic delay, the output is ready anyway)
  /////printf(">>> esperando...\n");
  while(pci_get_status(ptr) != 1);

  pci_send_command(ptr, 0);  // por Tiago
  msync(ptr, MMAP_SIZE, MS_SYNC); //talvez precise usar isso
}

void dump_device_mem_bytes(u32* devptr, int n) {
    FILE * fp = fopen("device_dump_bytes.dat", "w");
    if(!fp) {
        printf("\nNao pode fazer o dump para 'device_dump_bytes.dat'.\n");
        return;
    }

    fprintf(fp, "# Endereco:    Valor (hex)    Valor (dec)\n\n");

    int i;
    char valor;
    for(i=0; i<n; i++) {
        if( i%4 == 0) fprintf(fp, "#-----------------------------------\n");
        valor = *(char*)((u32)devptr+PCI_MEMORY+i);
        fprintf(fp, "%2X:    %2X    %i\n", i, valor, valor );
    }

    fclose(fp);
}


void dump_device_mem_words(u32* devptr, int n) {
    FILE * fp = fopen("device_dump_words.dat", "w");
    if(!fp) {
        printf("\nNao pode fazer o dump para 'device_dump_words.dat'.\n");
        return;
    }

    fprintf(fp, "# Endereco:    Valor (hex)    Valor (dec)\n\n");

    int i;
    u32 valor;
    for(i=0; i<n*4; i+=4) {
        valor = *(u32*)((u32)devptr+PCI_MEMORY+i);
        fprintf(fp, "%2X:    %8X    %i\n", i, valor, valor );
    }

    fclose(fp);
}


