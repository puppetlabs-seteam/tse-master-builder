require 'rbvmomi'
require 'yaml'

vm_name    = ENV['vm_name']    || abort('VM Name not set [export vm_name=X]. Full path to vm, ie folder1/folder2/vm')
fog_config = ENV['fog_config'] || abort('Fog configuration not set [export fog_config=X]')
datacenter = ENV['datacenter'] || abort('Datacenter not set [export datacenter=X]')


begin
  cfg = YAML.load_file(fog_config)
  vim = RbVmomi::VIM.connect  :host     => cfg[:default][:vsphere_server],
                              :user     => cfg[:default][:vsphere_username],
                              :password => cfg[:default][:vsphere_password],
                              :insecure => true

  dc = vim.serviceInstance.find_datacenter(datacenter)
  vm = dc.vmFolder.traverse(vm_name, RbVmomi::VIM::VirtualMachine) or abort("No VM named #{vm_name}")

  if vm.runtime.powerState == 'poweredOn'
    puts "Shutting down #{vm.name}"
    vm.PowerOffVM_Task.wait_for_completion
    puts "Halting #{vm.name} completed"
  end

  puts "Deleting #{vm.name}"
  vm.Destroy_Task
  puts "#{vm.name} Removed"
rescue
  abort("ERROR: #{$!}")
end



