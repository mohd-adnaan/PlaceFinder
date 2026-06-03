require 'xcodeproj'

project_path = '/Users/rehan/Projects/collabarations/ic4u/IndoorNavigationTACMEiOS/IndoorNavigationTACME.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

managers_group = project.main_group.find_subpath(File.join('IndoorNavigationTACME', 'Managers'), true)
managers_group.set_source_tree('<group>')
# Check if file is already added to avoid duplicates
unless managers_group.files.any? { |file| file.path == 'ARMappingManager.swift' }
    managers_file = managers_group.new_file('ARMappingManager.swift')
    target.add_file_references([managers_file])
end

views_group = project.main_group.find_subpath(File.join('IndoorNavigationTACME', 'Views'), true)
views_group.set_source_tree('<group>')
unless views_group.files.any? { |file| file.path == 'ARMappingView.swift' }
    views_file = views_group.new_file('ARMappingView.swift')
    target.add_file_references([views_file])
end

project.save
puts "Added files to Xcode project"
