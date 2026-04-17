# vivado -mode batch -source vivado.tcl

set project_name "fft32_project"
set part "xc7z010clg400-1"

# 1. Create the project
create_project $project_name ./$project_name -part $part -force

set src_dir [file normalize "./"]
set rtl_src [lsearch -all -inline -not [glob ${src_dir}/*.sv] "*_tb.sv"]

# 2. Add design sources
add_files -norecurse -fileset sources_1 ${rtl_src}
set_property file_type SystemVerilog [get_files ${rtl_src}]

if {[string equal [get_filesets -quiet sim_1] ""]} {
  create_fileset -simset sim_1
}

# 2. Add sim sources
set tb_src [glob ${src_dir}/*_tb.sv]

add_files -norecurse -fileset sim_1 ${tb_src}
set_property used_in_implementation false [get_files ${tb_src}]
set_property used_in_synthesis false [get_files ${tb_src}]
set_property file_type SystemVerilog [get_files ${tb_src}]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# 3. Copy const files
set sim_dir [file normalize "./${project_name}/${project_name}.sim/sim_1/behav/xsim/"]
if {![file exists $sim_dir]} {
  file mkdir $sim_dir
}

set hex_src [glob -nocomplain ${src_dir}/*.hex]
if ([llength $hex_src]) {
  foreach f $hex_src {
      file copy -force $f $sim_dir
  }
}

# 4. Copy waveconfig
set wcfg_src [glob -nocomplain ${src_dir}/*.wcfg]
if ([llength $wcfg_src]) {
  add_files -norecurse -fileset sim_1 $wcfg_src
}
