#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdarg.h>
#include <stddef.h>

typedef struct {
    uint32_t hClient;
    uint32_t hObject;
    uint32_t cmd;
    uint32_t flags;
    void    *params;
    uint32_t paramsSize;
    uint32_t status;
} __attribute__((aligned(8))) NVOS54_PARAMETERS;

int ioctl(int fd, unsigned long request, ...) {
    static int (*real_ioctl)(int, unsigned long, void *) = NULL;
    if (!real_ioctl) {
        real_ioctl = dlsym(RTLD_NEXT, "ioctl");
    }

    va_list ap;
    va_start(ap, request);
    void *arg = va_arg(ap, void *);
    va_end(ap);

    int ret = real_ioctl(fd, request, arg);

    /* NV_ESC_RM_CONTROL = 0xc020462a, NV0000_CTRL_CMD_GPU_GET_ATTACHED_IDS = 0x201 */
    if (ret == 0 && (request & 0xffffffffUL) == 0xc020462aUL && arg != NULL) {
        NVOS54_PARAMETERS *p = (NVOS54_PARAMETERS *)arg;
        if (p->cmd == 0x201U && p->status == 0U && p->params != NULL && p->paramsSize >= 128U) {
            uint32_t *ids = (uint32_t *)p->params;
            /* Keep only the internal laptop GPU (0x100 = PCI 0000:01:00.0) so nvidia-powerd
             * does not abort with "ERROR! UnSupported System." when an eGPU is attached. */
            int found_igpu = 0;
            for (int i = 0; i < 32 && ids[i] != 0xffffffffU; i++) {
                if (ids[i] == 0x100U) {
                    found_igpu = 1;
                    break;
                }
            }
            if (found_igpu) {
                ids[0] = 0x100U;
                for (int i = 1; i < 32; i++) {
                    ids[i] = 0xffffffffU;
                }
            }
        }
    }
    return ret;
}
