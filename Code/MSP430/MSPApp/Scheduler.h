#pragma once
#include <msp430.h>

class _MotionTask;
class SDTask;
class _Img;
class _BusyTimeoutTask;
using _Scheduler = Toastbox::Scheduler<
    _MotionTask,
    _SDTask,
    _ImgTask,
    _BusyTimeoutTask
>;
