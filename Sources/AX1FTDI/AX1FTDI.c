#include "AX1FTDI.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/usb/USB.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

enum {
    AX1_VENDOR_ID = 0x0403,
    AX1_PRODUCT_ID = 0x6001,
    AX1_DMX_FRAME_BYTES = 513,
    AX1_USB_TIMEOUT_MS = 150,
    AX1_FTDI_CHANNEL_A = 1,
    AX1_FTDI_VENDOR_OUT = 0x40,
    AX1_FTDI_SIO_RESET = 0,
    AX1_FTDI_SIO_MODEM_CTRL = 1,
    AX1_FTDI_SIO_FLOW_CTRL = 2,
    AX1_FTDI_SIO_SET_BAUDRATE = 3,
    AX1_FTDI_SIO_SET_DATA = 4,
    AX1_FTDI_BAUD_DIVISOR = 12, // 3 MHz reference / 250000 baud. FTDI AN232B-05.
    AX1_FTDI_LINE_8N2 = 8 | (2 << 11),
    AX1_FTDI_BREAK = 1 << 14,
    AX1_FTDI_DTR_RTS_LOW = 0x0300,
};

struct AX1FTDI {
    IOUSBInterfaceInterface500 **interface;
    UInt8 output_pipe;
    bool open;
    bool break_active;
};

static bool numeric_property(io_service_t service, CFStringRef key, uint32_t *result) {
    CFTypeRef property = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    if (!property) {
        return false;
    }

    int64_t value = 0;
    bool valid = CFGetTypeID(property) == CFNumberGetTypeID()
        && CFNumberGetValue((CFNumberRef)property, kCFNumberSInt64Type, &value)
        && value >= 0 && value <= UINT32_MAX;
    CFRelease(property);
    if (valid) {
        *result = (uint32_t)value;
    }
    return valid;
}

static bool matching_device(io_service_t device, uint32_t *location_id) {
    uint32_t vendor = 0, product = 0;
    return numeric_property(device, CFSTR("idVendor"), &vendor) && vendor == AX1_VENDOR_ID
        && numeric_property(device, CFSTR("idProduct"), &product) && product == AX1_PRODUCT_ID
        && numeric_property(device, CFSTR("locationID"), location_id) && *location_id != 0;
}

static kern_return_t usb_devices(io_iterator_t *devices) {
    CFMutableDictionaryRef match = IOServiceMatching("IOUSBHostDevice");
    if (!match) {
        return kIOReturnNoMemory;
    }
    return IOServiceGetMatchingServices(kIOMainPortDefault, match, devices);
}

int ax1_ftdi_list(uint32_t *location_ids, int capacity) {
    if (capacity < 0 || (capacity > 0 && !location_ids)) {
        return kIOReturnBadArgument;
    }
    if (capacity == 0) {
        return 0;
    }

    io_iterator_t devices = IO_OBJECT_NULL;
    kern_return_t status = usb_devices(&devices);
    if (status != KERN_SUCCESS) {
        return status;
    }

    int found = 0;
    io_service_t device;
    while (found < capacity && (device = IOIteratorNext(devices)) != IO_OBJECT_NULL) {
        uint32_t location_id = 0;
        if (matching_device(device, &location_id)) {
            location_ids[found++] = location_id;
        }
        IOObjectRelease(device);
    }
    IOObjectRelease(devices);
    return found;
}

static io_service_t first_usb_interface(io_service_t device) {
    io_iterator_t children = IO_OBJECT_NULL;
    if (IORegistryEntryGetChildIterator(device, kIOServicePlane, &children) != KERN_SUCCESS) {
        return IO_OBJECT_NULL;
    }

    io_service_t child;
    while ((child = IOIteratorNext(children)) != IO_OBJECT_NULL) {
        uint32_t interface_number = 0;
        if (IOObjectConformsTo(child, "IOUSBHostInterface")
            && numeric_property(child, CFSTR("bInterfaceNumber"), &interface_number)
            && interface_number == 0) {
            break;
        }
        IOObjectRelease(child);
    }
    IOObjectRelease(children);
    return child;
}

static kern_return_t find_interface(uint32_t location_id, io_service_t *interface) {
    io_iterator_t devices = IO_OBJECT_NULL;
    kern_return_t status = usb_devices(&devices);
    if (status != KERN_SUCCESS) {
        return status;
    }

    status = kIOReturnNoDevice;
    io_service_t device;
    while ((device = IOIteratorNext(devices)) != IO_OBJECT_NULL) {
        uint32_t candidate = 0;
        bool match = matching_device(device, &candidate) && candidate == location_id;
        if (match) {
            *interface = first_usb_interface(device);
            status = *interface != IO_OBJECT_NULL ? KERN_SUCCESS : kIOReturnNotReady;
        }
        IOObjectRelease(device);
        if (match) {
            break;
        }
    }
    IOObjectRelease(devices);
    return status;
}

static IOReturn control(AX1FTDI *device, UInt8 request, UInt16 value, UInt16 index) {
    IOUSBDevRequestTO control_request = {
        .bmRequestType = AX1_FTDI_VENDOR_OUT,
        .bRequest = request,
        .wValue = value,
        .wIndex = index,
        .wLength = 0,
        .noDataTimeout = AX1_USB_TIMEOUT_MS,
        .completionTimeout = AX1_USB_TIMEOUT_MS,
    };
    return (*device->interface)->ControlRequestTO(device->interface, 0, &control_request);
}

static IOReturn configure(AX1FTDI *device) {
    UInt8 endpoint_count = 0;
    IOReturn status = (*device->interface)->GetNumEndpoints(device->interface, &endpoint_count);
    if (status != kIOReturnSuccess) {
        return status;
    }

    for (unsigned int pipe = 1; pipe <= endpoint_count; pipe++) {
        UInt8 direction, endpoint, type, interval;
        UInt16 max_packet;
        status = (*device->interface)->GetPipeProperties(device->interface, (UInt8)pipe,
            &direction, &endpoint, &type, &max_packet, &interval);
        if (status != kIOReturnSuccess) {
            return status;
        }
        if (direction == kUSBOut && endpoint == 2 && type == kUSBBulk) {
            device->output_pipe = (UInt8)pipe;
            break;
        }
    }
    if (device->output_pipe == 0) {
        return kIOReturnNotFound;
    }

    // FT232R uses index 0 for the integer baud divisor. Other SIO requests use channel A.
    const struct {
        UInt8 request;
        UInt16 value;
        UInt16 index;
    } settings[] = {
        { AX1_FTDI_SIO_RESET, 0, AX1_FTDI_CHANNEL_A },
        { AX1_FTDI_SIO_SET_BAUDRATE, AX1_FTDI_BAUD_DIVISOR, 0 },
        { AX1_FTDI_SIO_SET_DATA, AX1_FTDI_LINE_8N2, AX1_FTDI_CHANNEL_A },
        { AX1_FTDI_SIO_FLOW_CTRL, 0, AX1_FTDI_CHANNEL_A },
        { AX1_FTDI_SIO_MODEM_CTRL, AX1_FTDI_DTR_RTS_LOW, AX1_FTDI_CHANNEL_A },
    };
    for (size_t step = 0; step < sizeof(settings) / sizeof(settings[0]); step++) {
        status = control(device, settings[step].request, settings[step].value, settings[step].index);
        if (status != kIOReturnSuccess) {
            return status;
        }
    }
    return kIOReturnSuccess;
}

int ax1_ftdi_open(uint32_t location_id, AX1FTDI **result) {
    if (!result) {
        return kIOReturnBadArgument;
    }
    *result = NULL;
    if (location_id == 0) {
        return kIOReturnBadArgument;
    }

    io_service_t interface = IO_OBJECT_NULL;
    kern_return_t status = find_interface(location_id, &interface);
    if (status != KERN_SUCCESS) {
        return status;
    }

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    status = IOCreatePlugInInterfaceForService(interface, kIOUSBInterfaceUserClientTypeID,
        kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(interface);
    if (status != kIOReturnSuccess || !plugin) {
        if (plugin) {
            IODestroyPlugInInterface(plugin);
        }
        return status != kIOReturnSuccess ? status : kIOReturnUnsupported;
    }

    AX1FTDI *device = calloc(1, sizeof(*device));
    if (!device) {
        IODestroyPlugInInterface(plugin);
        return kIOReturnNoMemory;
    }
    HRESULT query = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID500),
        (void **)&device->interface);
    IODestroyPlugInInterface(plugin);
    if (query != S_OK || !device->interface) {
        ax1_ftdi_close(device);
        return kIOReturnUnsupported;
    }

    status = (*device->interface)->USBInterfaceOpen(device->interface);
    if (status == kIOReturnSuccess) {
        device->open = true;
        status = configure(device);
    }
    if (status != kIOReturnSuccess) {
        ax1_ftdi_close(device);
        return status;
    }

    *result = device;
    return kIOReturnSuccess;
}

static void sleep_microseconds(long microseconds) {
    struct timespec remaining = { .tv_sec = 0, .tv_nsec = microseconds * 1000L };
    while (nanosleep(&remaining, &remaining) != 0 && errno == EINTR) {
        // Continue the unslept part after an interrupted wait.
    }
}

int ax1_ftdi_write(AX1FTDI *device, const uint8_t *buffer, int count) {
    if (!device || !device->open) {
        return kIOReturnNotOpen;
    }
    if (!buffer || count != AX1_DMX_FRAME_BYTES || buffer[0] != 0) {
        return kIOReturnBadArgument;
    }

    IOReturn status = control(device, AX1_FTDI_SIO_SET_DATA,
        AX1_FTDI_LINE_8N2 | AX1_FTDI_BREAK, AX1_FTDI_CHANNEL_A);
    if (status != kIOReturnSuccess) {
        return status;
    }
    device->break_active = true;
    sleep_microseconds(180);

    status = control(device, AX1_FTDI_SIO_SET_DATA, AX1_FTDI_LINE_8N2, AX1_FTDI_CHANNEL_A);
    if (status != kIOReturnSuccess) {
        return status;
    }
    device->break_active = false;
    sleep_microseconds(20);

    uint64_t write_started = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    status = (*device->interface)->WritePipeTO(device->interface, device->output_pipe,
        (void *)buffer, (UInt32)count, AX1_USB_TIMEOUT_MS, AX1_USB_TIMEOUT_MS);
    if (status == kIOReturnSuccess) {
        // USB completion can leave the FT232R's UART FIFO transmitting. Allow 13 ms
        // for up to 256 queued bytes and enough time for the entire 513-byte frame.
        uint64_t transfer_us = (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - write_started) / 1000;
        uint64_t drain_us = transfer_us < 12000 ? 25000 - transfer_us : 13000;
        sleep_microseconds((long)drain_us);
    }
    return status;
}

void ax1_ftdi_close(AX1FTDI *device) {
    if (!device) {
        return;
    }
    if (device->interface) {
        if (device->open) {
            if (device->break_active) {
                control(device, AX1_FTDI_SIO_SET_DATA, AX1_FTDI_LINE_8N2, AX1_FTDI_CHANNEL_A);
            }
            (*device->interface)->USBInterfaceClose(device->interface);
        }
        (*device->interface)->Release(device->interface);
    }
    free(device);
}

const char *ax1_ftdi_error(int status) {
    switch (status) {
        case kIOReturnSuccess: return "Success";
        case kIOReturnBadArgument: return "Invalid FTDI device location or DMX frame";
        case kIOReturnNoDevice: return "The selected FTDI USB device disconnected";
        case kIOReturnNotReady: return "macOS has not made the USB interface ready";
        case kIOReturnNotFound: return "No FT232R bulk output endpoint was found";
        case kIOReturnExclusiveAccess: return "A driver or another application holds the USB interface";
        case kIOReturnNotPermitted: return "macOS denied access to the USB interface";
        case kIOReturnNotOpen: return "The USB interface is closed";
        case kIOReturnTimeout: return "The USB transfer timed out";
        case kIOUSBPipeStalled: return "The USB device stalled a request";
        case kIOReturnNoMemory: return "macOS could not allocate a USB connection";
        case kIOReturnUnsupported: return "macOS could not provide the direct USB interface";
        default: {
            static _Thread_local char message[48];
            snprintf(message, sizeof(message), "macOS USB error 0x%08x", (unsigned int)status);
            return message;
        }
    }
}
