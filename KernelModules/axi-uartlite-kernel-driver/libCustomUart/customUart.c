#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include "customUart.h"



int customUartOpen(customUartHandle *handle, const char *devicePath) {
    if (!handle || !devicePath) return -1;

    handle -> fd = open(devicePath, O_RDWR | O_NOCTTY);
    if(handle -> fd < 0) {
        perror("Failed to open device");
        return -1;
    }
    strcpy(handle->devicePath, devicePath);
    return 0;
}

void customUartClose(customUartHandle *handle) {
    if(handle && handle -> fd > 0) {
        close(handle->fd);
        handle -> fd = -1;
    }
}

ssize_t customUartWrite(customUartHandle *handle, const void *data, size_t length) {
    if(!handle || handle -> fd < 0) {
        perror("No file discriptor\n");
        return -1;
    }
    return write(handle -> fd, data, length);
}

ssize_t customUartRead(customUartHandle *handle, void *buffer, size_t length) {
    if(!handle || handle -> fd < 0) {
        perror("No file discriptor\n");
        return -1;
    }
    return read(handle -> fd, buffer, length);
}


