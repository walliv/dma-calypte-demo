

create_ip -name hbm -vendor xilinx.com -library ip -version 1.0 -module_name hbm_ip

set_property -dict [list \
    CONFIG.Component_Name {hbm_ip} \
    CONFIG.USER_APB_EN {false} \
    CONFIG.USER_HBM_DENSITY {16GB} \
    CONFIG.USER_SWITCH_ENABLE_00 {FALSE} \
    CONFIG.USER_SWITCH_ENABLE_01 {FALSE} \
    CONFIG.USER_XSDB_INTF_EN {FALSE} \
] [get_ips hbm_ip]
