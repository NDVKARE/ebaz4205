1. Power Domain
2. Clock
3. Reset
4. Isolation
5. Retention
6. Wakeup
7. Voltage / DVFS
8. Sensor
9. System Power
10. Error/Fault
11. Watchdog
12. Thermal


pmu_fw/
|
+-- scmi/
|   +-- scmi_base.c
|   +-- scmi_power.c
|   +-- scmi_clock.c
|   +-- scmi_reset.c
|   +-- scmi_perf.c
|   +-- scmi_sensor.c
|
+-- power/
|   +-- power_domain.c
|   +-- isolation.c
|   +-- retention.c
|   +-- power_sequence.c
|
+-- clock/
|   +-- clock.c
|   +-- pll.c
|   +-- clock_mux.c
|
+-- reset/
|   +-- reset.c
|
+-- voltage/
|   +-- regulator.c
|   +-- dvfs.c
|
+-- system/
|   +-- suspend.c
|   +-- wakeup.c
|   +-- shutdown.c
|
+-- safety/
|   +-- watchdog.c
|   +-- fault.c
|   +-- error_log.c
|
+-- sensor/
|   +-- temperature.c
|   +-- voltage_monitor.c
|
+-- platform/
    +-- soc_regs.h
    +-- platform.c


*****
SCMI POWER_STATE_SET(domain, OFF)
-------------------------------------
1. Check domain dependency
2. Disable incoming transactions
3. Wait idle
4. Save context
5. Enable retention
6. Gate clock
7. Assert isolation
8. Assert reset
9. Turn off power switch
10. Wait PGOOD low
11. Update internal state
12. Reply SCMI SUCCESS



                         Linux / RTOS
                              |
                             SCMI
                              |
                              v
                     +----------------+
                     | SCP / PMU FW   |
                     +----------------+
                              |
        +---------+-----------+-----------+----------+
        |         |           |           |          |
      Power     Clock       Reset       Perf       Sensor
        |         |           |           |          |
        |         |           |           +----+-----+
        |         |           |                |
        |         |           |               DVFS
        |         |           |                |
        v         v           v                v
     Power      PLL/Mux    Reset Ctrl       PMIC
     Switch
        |
        +---- Isolation
        |
        +---- Retention
        |
        +---- Power-good



8. Error/Fault management
Đây cũng là chức năng rất quan trọng nhưng đôi khi không được nhắc đến cùng SCMI.
SCP có thể monitor:

Power good failure
PLL unlock
Voltage out-of-range
Over-temperature
ECC error
Watchdog timeout
Clock failure
Brownout

Sau đó quyết định:

log only
reset peripheral
reset domain
power cycle domain
system reset
emergency shutdown

****
sensor/
  temperature.c
  voltage.c
  current.c

thermal/
  thermal_policy.c
  thermal_trip.c
  thermal_action.c

****
  Ví dụ thermal_trip.c:
T0 = 80°C  -> warning
T1 = 90°C  -> throttle
T2 = 100°C -> aggressive throttle
T3 = 110°C -> shutdown


***
Về kiến trúc:
SCMI Power Domain
        |
        v
SCP Power Manager
        |
        +-- Power switch
        +-- Isolation
        +-- Retention
        +-- Reset
        +-- Clock
        +-- PGOOD

Power Protocol là interface, còn isolation, retention, power switch là các mechanism bên dưới.

****
SCMI Clock cho phép kiểu:
discover clock
get rate
set rate
enable
disable

Bên dưới SCP có thể điều khiển:
Clock Protocol
      |
      v
Clock Manager
      |
      +-- PLL
      +-- divider
      +-- mux
      +-- gate




                     Linux
                       |
                     SCMI
                       |
       +---------------+---------------+
       |               |               |
     Power           Clock           Reset
       |               |               |
   Performance       Sensor          Voltage
       |               |
   System Power     Pin Control
       |
       v
+------------------------------------------+
|               Ibex PMU FW                |
|                                          |
| SCMI Protocol Layer                      |
+------------------------------------------+
|             PM Policy Layer              |
|                                          |
| Power sequencing / DVFS / Thermal        |
| Wakeup / Dependency / Fault policy       |
+------------------------------------------+
|              HW Control                  |
|                                          |
| Isolation   Retention   Reset             |
| Clock/PLL   Power switch Voltage/PMIC     |
| Sensor HW   PGOOD       Wake source       |
+------------------------------------------+



Muốn Linux dùng SCMI để nói chuyện với Ibex trên PL, thì sẽ phải build Linux/PetaLinux để thêm phần Linux-side support tương ứng.


https://www.amd.com/en/support/downloads/adaptive-socs-and-fpgas/embedded-software.html