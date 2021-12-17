#pragma once
#include <msp430.h>
#include "Toastbox/Task.h"

class _MotionTask;
class _SDTask;
class _ImgTask;
class _BusyTimeoutTask;

using Scheduler = Toastbox::Scheduler<
    _MotionTask,
    _SDTask,
    _ImgTask,
    _BusyTimeoutTask
>;
