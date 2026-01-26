#ifndef CUSTOMUART_H
#define CUSTOMUART_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int fd;
    char devicePath[64];
} customUartHandle;

int customUartOpen(customUartHandle *handle, const char *devicePath);
void customUartClose(customUartHandle *handle);
ssize_t customUartWrite(customUartHandle *handle, const void *data, size_t length);
ssize_t customUartRead(customUartHandle *handle, void *buffer, size_t length);

#ifdef __cplusplus
}
#endif

#endif