set_property PACKAGE_PIN W13 [get_ports led6_green_n]
set_property IOSTANDARD LVCMOS33 [get_ports led6_green_n]
set_property PACKAGE_PIN W14 [get_ports led6_red_n]
set_property IOSTANDARD LVCMOS33 [get_ports led6_red_n]

# DATA1 pins 5, 6, 7, 8; GPIO IDs 1, 2, 3, 4 respectively.
# https://github.com/xjtuecho/EBAZ4205/wiki/Data-Connectors
# Use individual commands: Vivado 2015.1's synthesis XDC parser rejects -dict.
set_property PACKAGE_PIN A20 [get_ports {data_gpio[0]}]
set_property PACKAGE_PIN H16 [get_ports {data_gpio[1]}]
set_property PACKAGE_PIN B19 [get_ports {data_gpio[2]}]
set_property PACKAGE_PIN B20 [get_ports {data_gpio[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {data_gpio[*]}]
set_property DRIVE 4 [get_ports {data_gpio[*]}]
set_property SLEW SLOW [get_ports {data_gpio[*]}]
