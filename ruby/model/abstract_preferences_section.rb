require 'singleton'

class Preferences
  class << self
    # A hash of all default values for the user defaults
    def default_values
      @default_values ||= {}
    end
    
    # Registers the default values with NSUserDefaults.standardUserDefaults
    # Called at the end of evaluating model/preferences.rb
    def register_default_values!
      NSUserDefaults.standardUserDefaults.registerDefaults(default_values)
    end
  end
  
  class AbstractPreferencesSection
    include Singleton
    
    class << self
      # The key in the preferences that represents the section class.
      #
      #   Preferences::General.section_defaults_key # => "Preferences.General"
      def section_defaults_key
        @section_defaults_key ||= name.gsub('::', '.')
      end
      
      # Defines a reader and writer method for a user defaults key for this section.
      #
      #   # Defines #confirm_quit and #confirm_quit= and <tt>true</tt> as it's default value.
      #   defaults_accessor :confirm_quit, true
      def defaults_accessor(name, default_value)
        key_path = "#{section_defaults_key}.#{name}"
        Preferences.default_values[key_path] = default_value
        
        class_eval do
          define_method(name) do
            NSUserDefaults.standardUserDefaults[key_path].to_ruby
          end
          
          define_method("#{name}=") do |value|
            NSUserDefaults.standardUserDefaults[key_path] = value
          end
        end
        
        key_path
      end
      
      # Besides defining a reader and writer method via defaults_accessor,
      # it also defines a reader method which returns an array of strings
      # wrapped in KVO compatible string wrappers.
      #
      # The name of the wrapper class is defined by <tt>wrapper_class_name</tt>
      # and can be used as the `Class Name' of a NSArrayController.
      # The wrapper exposes `string' as a KVC accessor to which a NSTableColumn can be bound.
      #
      #   # Defines #highlight_words, #highlight_words=, and #highlight_words_wrapped
      #   string_array_defaults_accessor :highlight_words, [], 'HighlightWordWrapper'
      def string_array_defaults_accessor(name, default_value, wrapper_class_name)
        wrapper = eval("class ::#{wrapper_class_name} < StringArrayWrapper; self end")
        wrapper.key_path = defaults_accessor(name, default_value)
        
        class_eval do
          define_method("#{name}_wrapped") do
            ary = []
            send(name).each_with_index { |string, index| ary << wrapper.alloc.initWithString_index(string, index) }
            ary
          end
        end
      end
    end
  end
  
  class StringArrayWrapper < OSX::NSObject
    class << self
      attr_accessor :key_path
      
      def array
        NSUserDefaults.standardUserDefaults[key_path].to_ruby
      end
      
      def array=(array)
        NSUserDefaults.standardUserDefaults[key_path] = array
      end
      
      def destroy(wrappers, new_wrappers)
        klass = wrappers.first.class
        
        keep = new_wrappers.map { |w| w.index }
        wrappers_to_destroy = wrappers.reject { |w| keep.include?(w.index) }
        
        # Remove the wrappers to destroy from the `wrappers' array
        wrappers_to_destroy.sort_by { |w| w.index }.reverse.each do |wrapper_to_destroy|
          wrappers.delete_at(wrapper_to_destroy.index)
        end
        
        # Set the new correct indices on the remaining wrappers
        new_wrappers.each_with_index do |wrapper, new_index|
          wrapper.index = new_index
        end
        
        # Assign the new result array of strings
        klass.array = wrappers.map { |wrapper| wrapper.string }
      end
    end
    
    kvc_accessor :string
    attr_accessor :index
    
    def initWithString_index(string, index)
      if init
        @string, @index = string, index
        self
      end
    end
    
    def array
      self.class.array
    end
    
    def array=(array)
      self.class.array = array
    end
    
    def string=(string)
      @string = string
      set_string!
    end
    
    def set_string!
      if @index
        ary = array
        ary[@index] = string
        self.array = ary
      else
        ary = array
        ary << @string
        self.array = ary
        @index = ary.length - 1
      end
    end
    
    def inspect
      "#<#{self.class.name}:#{object_id} string=\"#{@string}\" key_path=\"#{self.class.key_path}\" index=\"#{@index}\">"
    end
  end
  
  module StringArrayWrapperHelper
    def string_array_wrapper_accessor(name, path_to_eval_to_object)
      kvc_accessor(name)
      
      class_eval %{
        def #{name}
          @#{name} ||= #{path_to_eval_to_object}_wrapped
        end
        
        def #{name}=(new_wrappers)
          if new_wrappers.length < #{name}.length
            Preferences::StringArrayWrapper.destroy(#{name}, new_wrappers)
          end
          @#{name} = new_wrappers
        end
      }, __FILE__, __LINE__
    end
  end
end