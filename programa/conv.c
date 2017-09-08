
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h> 
#include <fcntl.h>
#include <unistd.h>

#include "pcie_memmap.h"

int main()
{
    unsigned int qtde_nums = 128;

    FILE * fp_entrada = fopen("entrada.dat", "r");

    if(!fp_entrada) {
        printf("Fornecer o arquivo \"entrada.dat\".\n");
        exit(1);
    }

    int i;

    int numeros[qtde_nums];
    u32 resultados[qtde_nums];

    for(i=0 ; i<qtde_nums ; i++) {
        fscanf(fp_entrada, "%i", (numeros+i) );
    }

    for(i=0 ; i<qtde_nums ; i++) {
        resultados[i] = (u32)0;
    }

    printf("\nTeste da operacao na FPGA:\n\n");
    printf("Entrada = ");

    for(i=0 ; i<qtde_nums ; ++i) {
        printf("%i ; ", numeros[i]);
    }

    printf("\n\n");

    // FPGA
    u32* ptr = get_device();

    move(ptr, (u32*) numeros, qtde_nums);
    executar(ptr);
    get(ptr, resultados, qtde_nums);

    printf("\nFazendo dump...\n");
    dump_device_mem_bytes(ptr, 1024);
    dump_device_mem_words(ptr, 256);
    printf("Dump feito.\n");

    close_device(ptr);
    // END FPGA

    printf("Saida = ");

    for(i=0 ; i<qtde_nums ; ++i) {
        printf("%i ; ", ((int*)resultados)[i] );
    }

    printf("\n\n");
    
    return 0;
}

/*

// just printing a 128-bit word in hex
void printhex128(u8* str){
  int i;
  for(i=0; i<16; i++)
    printf("%2x", str[i]);
  printf("\n");
}

int main2() {
  u32* ptr = get_device();
  
  // Key and plaintext in hex
  //000102030405060708090A0B0C0D0E0F
  u8 txt[] = {0x00, 0x01, 0x02, 0x03,
	      0x04, 0x05, 0x06, 0x07,
	      0x08, 0x09, 0x0A, 0x0B,
	      0x0C, 0x0D, 0x0E, 0x00};

  //00112233445566778899AABBCCDDEEFF
  u8 key[] = {0x00, 0x11, 0x22, 0x33,
	      0x44, 0x55, 0x66, 0x77,
	      0x88, 0x99, 0xAA, 0xBB,
	      0xCC, 0xDD, 0xEE, 0xFF};

  printf("KEY: ");
  printhex128(key);
  
  printf("PLAINTEXT: "); 
  printhex128(txt);

  u8 cipher_fpga[16];

  // Call AES on FPGA
  pci_aes128(ptr, (u32*)cipher_fpga, (u32*)key, (u32*)txt);
      
  // Print the results
  printf("CIPHERTEXT(FPGA): ");
  printhex128(cipher_fpga);

  close_device(ptr);

 return 0;
}

*/
