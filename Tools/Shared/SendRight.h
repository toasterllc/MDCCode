#pragma once
#include <mach/mach.h>
#include <cassert>
#include "Toastbox/RefCounted.h"

void _SendRightRetain(mach_port_t x) {
    kern_return_t kr = mach_port_mod_refs(mach_task_self(), x, MACH_PORT_RIGHT_SEND, 1);
    // KERN_INVALID_RIGHT is returned when the send right is actually a dead name,
    // so we need to handle that case specially, since we still want to retain it.
    assert(kr==KERN_SUCCESS || kr==KERN_INVALID_RIGHT);
    if (kr == KERN_INVALID_RIGHT) {
        kr = mach_port_mod_refs(mach_task_self(), x, MACH_PORT_RIGHT_DEAD_NAME, 1);
        assert(kr == KERN_SUCCESS);
    }
}

void _SendRightRelease(mach_port_t x) {
    kern_return_t kr = mach_port_deallocate(mach_task_self(), x);
    assert(kr == KERN_SUCCESS);
}

using SendRight = RefCounted<mach_port_t, _SendRightRetain, _SendRightRelease>;
