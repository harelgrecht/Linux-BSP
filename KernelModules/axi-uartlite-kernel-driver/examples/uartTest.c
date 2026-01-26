#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include "../libCustomUart/CustomUart.h"

#define UART_DEV "/dev/ttyUART0"
#define BUF_SIZE 512
#define TEST_STRING "The quick brown fox jumps over the lazy dog 1234567890\n"
#define ROUNDS_OF_TESTS 100

void random_delay() {
    struct timespec ts = {0, (rand() % 100) * 1000000}; // 0-100ms
    nanosleep(&ts, NULL);
}

int main() {
    srand(time(NULL));

    customUartHandle uartHandler;

    if(customUartOpen(&uartHandler, UART_DEV) < 0) {
        return 1;
    }

    printf("Starting UART Loopback Test on %s\n", UART_DEV);

    char read_buf[BUF_SIZE] = {0};
    ssize_t written, read_bytes;
    unsigned int i, passes = 0, failures = 0;

    // Multiple rounds of testing
    for (i = 0; i < ROUNDS_OF_TESTS; i++) {
        const char *msg = TEST_STRING;
        size_t msg_len = strlen(msg);

        // Write message to UART
        written = customUartWrite(&uartHandler, msg, msg_len);
        if (written != msg_len) {
            perror("write");
            failures++;
            continue;
        }

        random_delay(); // optional random delay

        // Read response
        size_t total_read = 0;
        while (total_read < msg_len) {
            read_bytes = customUartRead(&uartHandler, read_buf + total_read, msg_len - total_read);
            if (read_bytes < 0) {
                perror("read");
                failures++;
                break;
            }
            total_read += read_bytes;
        }

        if (strncmp(msg, read_buf, msg_len) == 0) {
            passes++;
        } else {
            fprintf(stderr, "Mismatch!\nExpected: %s\nGot: %s\n", msg, read_buf);
            failures++;
        }

        if ((i % ROUNDS_OF_TESTS) == 0)
            printf("Test iteration %u complete: %u passes, %u failures\n", i, passes, failures);
    }

    printf("UART Loopback Test Complete. Passes: %u, Failures: %u\n", passes, failures);

    customUartClose(&uartHandler);

    if (failures == 0) {
        printf("✅ All tests passed: UART interrupt-driven RX and polling TX working well!\n");
        return 0;
    } else {
        printf("❌ Some tests failed.\n");
        return 1;
    }
}
