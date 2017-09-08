// FPGA memap

#ifndef PCIE_MEMMAP_H

#define PCIE_MEMMAP_H

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long u64;

// finds PCI base address by vendor & device id    
int pci_read_base_address(int vendor, int device);

// read n bytes from an address
/*inline*/ void pci_mm_read(u32* dst, u32* devptr, int offset, int n);

// write n bytes to an address
/*inline*/ void pci_mm_write(u32* src, u32* devptr, int offset, int n);

// write to output PIO
/*inline*/ void pci_send_command(u32* ptr, int cmd);

// read from input PIO
/*inline*/ u32 pci_get_status(u32* ptr);



// run AES operation
/*inline*/ void pci_aes128(u32* ptr, u32* cipher, u32* key, u32* txt);


// Getting the device pointer
u32* get_device();

void close_device(u32* ptr);

// mover dados para a memoria compartilhada
void move(u32* ptr, u32* data, int n);

// ler dados da memoria compartilhada
void get(u32* ptr, u32* dest, int n);

//
void executar(u32* ptr);


void dump_device_mem_bytes(u32* devptr, int n);

void dump_device_mem_words(u32* devptr, int n);

#endif /* PCIE_MEMMAP_H */

