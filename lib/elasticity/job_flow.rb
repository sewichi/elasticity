module Elasticity

  class JobFlowRunningError < StandardError; end
  class JobFlowNotStartedError < StandardError; end
  class JobFlowMissingStepsError < StandardError; end

  class JobFlow

    attr_accessor :action_on_failure
    attr_accessor :ec2_key_name
    attr_accessor :security_configuration
    attr_accessor :name
    attr_accessor :hadoop_version
    attr_accessor :instance_count
    attr_accessor :log_uri
    attr_accessor :master_instance_type
    attr_accessor :slave_instance_type
    attr_accessor :ami_version
    attr_accessor :keep_job_flow_alive_when_no_steps
    attr_accessor :ec2_subnet_id
    attr_accessor :ec2_subnet_ids
    attr_accessor :placement
    attr_accessor :visible_to_all_users
    attr_accessor :jobflow_id
    attr_accessor :defaults
    attr_reader :access_key
    attr_reader :secret_key
    attr_reader :session_token
    attr_accessor :additional_master_security_groups
    attr_accessor :additional_slave_security_groups

    def initialize(access=nil, secret=nil, session_token=nil)

      @access_key = access
      @secret_key = secret

      @bootstrap_actions = []
      @jobflow_steps = []
      @installed_steps = []

      @instance_groups = {}
      @instance_fleets = {}
      @instance_count = 2
      @master_instance_type = 'm1.small'
      @slave_instance_type = 'm1.small'

      @access_key = access
      @secret_key = secret
      @session_token = session_token
    end

    def self.from_jobflow_id(access, secret, jobflow_id, region = 'us-east-1', options = {})
      JobFlow.new(access, secret, options[:session_token]).tap do |j|
        j.instance_variable_set(:@region, region)
        j.instance_variable_set(:@jobflow_id, jobflow_id)
        j.instance_variable_set(:@session_token, options[:session_token])
      end
    end

    def instance_count=(count)
      raise ArgumentError, "Instance count cannot be set to less than 2 (requested #{count})" unless count > 1
      @instance_groups[:core].count = count - 1
      @instance_count = count
    end

    def master_instance_type=(type)
      @instance_groups[:master].type = type
      @master_instance_type = type
    end

    def slave_instance_type=(type)
      @instance_groups[:core].type = type
      @slave_instance_type = type
    end

    def add_bootstrap_action(bootstrap_action)
      if is_jobflow_running?
        raise JobFlowRunningError, 'To modify bootstrap actions, please create a new job flow.'
      end
      @bootstrap_actions << bootstrap_action
    end

    def check_instances
      if !@instance_groups.empty? and !@instance_fleets.empty?
        raise ArgumentError, 'Instance groups and instance fleets are mutually exclusive!'
      end
    end

    def set_master_instance_group(instance_group)
      instance_group.role = 'MASTER'
      @instance_groups[:master] = instance_group
      check_instances
    end

    def set_core_instance_group(instance_group)
      instance_group.role = 'CORE'
      @instance_groups[:core] = instance_group
      check_instances
    end

    def set_task_instance_group(instance_group)
      instance_group.role = 'TASK'
      @instance_groups[:task] = instance_group
      check_instances
    end

    def set_master_instance_fleet(instance_fleet)
      instance_fleet.role = 'MASTER'
      @instance_fleets[:master] = instance_fleet
      check_instances
    end

    def set_core_instance_fleet(instance_fleet)
      instance_fleet.role = 'CORE'
      @instance_fleets[:core] = instance_fleet
      check_instances
    end

    def set_task_instance_fleet(instance_fleet)
      instance_fleet.role = 'TASK'
      @instance_fleets[:task] = instance_fleet
      check_instances
    end

    def add_step(jobflow_step)
      if is_jobflow_running?
        jobflow_steps = []
        if jobflow_step.requires_installation? && !@installed_steps.include?(jobflow_step.class)
          jobflow_steps.concat(jobflow_step.aws_installation_steps)
        end
        jobflow_steps << jobflow_step.to_aws_step(self)
        emr.add_jobflow_steps(@jobflow_id, {:steps => jobflow_steps})
      else
        @jobflow_steps << jobflow_step
      end
    end

    def add_steps(jobflow_steps)
      if is_jobflow_running?
        #ignoring requires_installation as it pertains to pig/hive that we do not support
        emr.add_jobflow_steps(@jobflow_id, {steps: jobflow_steps.map { |s| s.to_aws_step(self) }} )
      else
        @jobflow_steps += jobflow_steps
      end
    end

    def run
      if is_jobflow_running?
        raise JobFlowRunningError, 'Cannot run a job flow multiple times.  To do more with this job flow, please use #add_step.'
      end
      @jobflow_id = emr.run_job_flow(jobflow_config)
    end

    def shutdown
      if !is_jobflow_running?
        raise JobFlowNotStartedError, 'Cannot #shutdown a job flow that has not yet been #run.'
      end
      emr.terminate_jobflows(@jobflow_id)
    end

    def status
      if !is_jobflow_running?
        raise JobFlowNotStartedError, 'Please #run this job flow before attempting to retrieve status.'
      end
      emr.describe_jobflow(@jobflow_id)
    end

    private

    def emr
      @region ||= (@placement && @placement.match(/(\w+-\w+-\d+)/)[0]) || 'us-east-1'
      @emr ||= Elasticity::EMR.new(@access_key, @secret_key, :region => @region, :session_token => @session_token)
    end

    def is_jobflow_running?
      !@jobflow_id.nil?
    end

    def jobflow_config
      config = jobflow_preamble
      config[:steps] = jobflow_steps
      config[:log_uri] = @log_uri if @log_uri
      config[:bootstrap_actions] = @bootstrap_actions.map{|a| a.to_aws_bootstrap_action} unless @bootstrap_actions.empty?
      config[:security_configuration] = @security_configuration if @security_configuration
      config
    end

    def jobflow_preamble
      preamble = @defaults

      preamble[:name] = @name unless @name.nil?

      major_version = @ami_version.split('.').first.to_i if @ami_version
      if major_version && major_version >= 4
        preamble[:release_label] = "emr-#@ami_version"
        preamble.delete(:ami_version)
      else
        preamble[:ami_version] = @ami_version unless @ami_version.nil?
      end

      preamble[:visible_to_all_users] = @visible_to_all_users unless @visible_to_all_users.nil?

      preamble[:instances] ||= {}
      preamble[:instances][:keep_job_flow_alive_when_no_steps] = @keep_job_flow_alive_when_no_steps unless @keep_job_flow_alive_when_no_steps.nil?
      preamble[:instances][:hadoop_version] = @hadoop_version unless @hadoop_version.nil?
      preamble[:instances][:instance_groups] = jobflow_instance_groups unless @instance_groups.empty?
      preamble[:instances][:instance_fleets] = jobflow_instance_fleets unless @instance_fleets.empty?

      @ec2_key_name ||= preamble[:ec2_key_name]

      preamble[:instances].merge!(:ec2_key_name => @ec2_key_name) if @ec2_key_name
      preamble[:instances].merge!(:additional_master_security_groups => @additional_master_security_groups) if @additional_master_security_groups
      preamble[:instances].merge!(:additional_slave_security_groups => @additional_slave_security_groups) if @additional_slave_security_groups

      preamble[:instances][:placement] = {:availability_zone => @placement} if @placement

      preamble[:placement] = {:availability_zone => @placement} if @placement
      if @ec2_subnet_id
        preamble[:instances].merge!(:ec2_subnet_id => @ec2_subnet_id)
        preamble[:instances].delete(:placement)
      elsif @ec2_subnet_ids
        preamble[:instances].merge!(:ec2_subnet_ids => @ec2_subnet_ids)
        preamble[:instances].delete(:placement)
      end

      preamble
    end

    def jobflow_steps
      steps = []
      @jobflow_steps.each do |step|
        if step.class.send(:requires_installation?) && !@installed_steps.include?(step.class)
          steps.concat(step.class.send(:aws_installation_steps))
          @installed_steps << step.class
        end
        steps << step.to_aws_step(self)
      end
      steps
    end

    def jobflow_instance_groups
      groups = [:master, :core, :task].map{|role| @instance_groups[role]}.compact
      groups.map(&:to_aws_instance_config)
    end

    def jobflow_instance_fleets
      fleets = [:master, :core, :task].map{|role| @instance_fleets[role]}.compact
      fleets.map(&:to_aws_instance_config)
    end

  end

end
