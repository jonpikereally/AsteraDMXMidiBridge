#ifndef AX1FTDI_H
#define AX1FTDI_H

#include <stdint.h>

typedef struct AX1FTDI AX1FTDI;

// Enumerates FTDI 0403:6001 locations without opening the devices. Returns the number
// written, or a negative status from IOKit. A buffer of capacity zero is valid.
int ax1_ftdi_list(uint32_t *location_ids, int capacity);

// Opens one USB interface without taking it away from another application or driver.
// Control requests and writes have finite USB timeouts. Use these functions on one worker.
int ax1_ftdi_open(uint32_t location_id, AX1FTDI **result);
int ax1_ftdi_write(AX1FTDI *device, const uint8_t *buffer, int count);
void ax1_ftdi_close(AX1FTDI *device);

// A descriptive, thread-local error string. Open and write return zero on success.
const char *ax1_ftdi_error(int status);

#endif
