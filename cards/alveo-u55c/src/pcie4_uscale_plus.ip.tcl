create_ip -name pcie4c_uscale_plus -vendor xilinx.com -library ip -version 1.0 -module_name pcie4_uscale_plus
set_property -dict [list \
  CONFIG.Component_Name {pcie4_uscale_plus} \
  CONFIG.MSI_X_OPTIONS {MSI-X_External} \
  CONFIG.PF0_DEVICE_ID {c000} \
  CONFIG.PF0_SUBSYSTEM_ID {c000} \
  CONFIG.PF0_SUBSYSTEM_VENDOR_ID {18ec} \
  CONFIG.PL_LINK_CAP_MAX_LINK_SPEED {8.0_GT/s} \
  CONFIG.PL_LINK_CAP_MAX_LINK_WIDTH {X8} \
  CONFIG.axisten_if_enable_client_tag {true} \
  CONFIG.ext_pcie_cfg_space_enabled {true} \
  CONFIG.mode_selection {Advanced} \
  CONFIG.pf0_bar0_64bit {true} \
  CONFIG.pf0_bar0_scale {Megabytes} \
  CONFIG.pf0_bar0_size {64} \
  CONFIG.pf0_bar2_64bit {true} \
  CONFIG.pf0_bar2_enabled {true} \
  CONFIG.pf0_bar2_scale {Megabytes} \
  CONFIG.pf0_bar2_size {16} \
  CONFIG.pf0_base_class_menu {Network_controller} \
  CONFIG.pf0_dsn_enabled {true} \
  CONFIG.pf0_msi_enabled {false} \
  CONFIG.pf0_sub_class_interface_menu {Ethernet_controller} \
  CONFIG.pf0_vc_cap_enabled {false} \
  CONFIG.vendor_id {18ec} \
] [get_ips pcie4_uscale_plus]
