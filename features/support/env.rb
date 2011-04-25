
require 'rubygems'
require 'bundler'
Bundler.setup

$:.unshift(File.join(File.dirname(__FILE__), '../../lib/client/lib'))
require 'json/pure'
require 'singleton'
require 'spec'
require 'vmc_base'
require 'curb'
require 'pp'

# The integration test automation based on Cucumber uses the AppCloudHelper as a driver that takes care of
# of all interactions with AppCloud through the VCAP::BaseClient intermediary.
#
# Author:: A.B.Srinivasan
# Copyright:: Copyright (c) 2010 VMware Inc.

TEST_AUTOMATION_USER_ID = "tester@vcap.example.com"
TEST_AUTOMATION_PASSWORD = "tester"
SIMPLE_APP = "simple_app"
REDIS_LB_APP = "redis_lb_app"
ENV_TEST_APP = "env_test_app"
TINY_JAVA_APP = "tiny_java_app"
SIMPLE_DB_APP = "simple_db_app"
SIMPLE_RACK_APP = "simple_rack_app"
BROKEN_APP = "broken_app"
RAILS3_APP = "rails3_app"
JPA_APP = "jpa_app"
HIBERNATE_APP = "hibernate_app"
DBRAILS_APP = "dbrails_app"
DBRAILS_BROKEN_APP = "dbrails_broken_app"
GRAILS_APP = "grails_app"
ROO_APP = "roo_app"

After do
  AppCloudHelper.instance.delete_user
end

After("@creates_simple_app") do
  AppCloudHelper.instance.delete_app_internal SIMPLE_APP
end

After("@creates_tiny_java_app") do
  AppCloudHelper.instance.delete_app_internal TINY_JAVA_APP
end

After("@creates_simple_db_app") do
  AppCloudHelper.instance.delete_app_internal SIMPLE_DB_APP
end

After("@creates_simple_rack_app") do
  AppCloudHelper.instance.delete_app_internal SIMPLE_RACK_APP
end

After("@creates_redis_lb_app") do
  AppCloudHelper.instance.delete_app_internal REDIS_LB_APP
end


After("@creates_env_test_app") do
  AppCloudHelper.instance.delete_app_internal ENV_TEST_APP
end

After("@creates_broken_app") do
  AppCloudHelper.instance.delete_app_internal BROKEN_APP
end

After("@creates_rails3_app") do
  AppCloudHelper.instance.delete_app_internal RAILS3_APP
end

After("@creates_jpa_app") do
  AppCloudHelper.instance.delete_app_internal JPA_APP
end

After("@creates_hibernate_app") do
  AppCloudHelper.instance.delete_app_internal HIBERNATE_APP
end

After("@creates_dbrails_app") do
  AppCloudHelper.instance.delete_app_internal DBRAILS_APP
end

After("@creates_dbrails_broken_app") do
  AppCloudHelper.instance.delete_app_internal DBRAILS_BROKEN_APP
end

After("@creates_grails_app") do
  AppCloudHelper.instance.delete_app_internal GRAILS_APP
end

After("@creates_roo_app") do
  AppCloudHelper.instance.delete_app_internal ROO_APP
end

at_exit do
  AppCloudHelper.instance.cleanup
end

['TERM', 'INT'].each { |s| trap(s) { AppCloudHelper.instance.cleanup; Process.exit! } }

class AppCloudHelper
  include Singleton

  def initialize
    @last_registered_user, @last_login_token = nil
    # Go through router endpoint for CloudController
    @target = ENV['VCAP_BVT_TARGET'] || 'vcap.me'
    @registered_user = ENV['VCAP_BVT_USER']
    @registered_user_passwd = ENV['VCAP_BVT_USER_PASSWD']
    @base_uri = "http://api.#{@target}"
    @droplets_uri = "#{@base_uri}/apps"
    @resources_uri = "#{@base_uri}/resources"
    @services_uri = "#{@base_uri}/services"
    @suggest_url = @target

    puts "\n** VCAP_BVT_TARGET = '#{@target}' (set environment variable to override) **"
    puts "** Running as user: '#{test_user}' (set environment variables VCAP_BVT_USER / VCAP_BVT_USER_PASSWD to override) **"
    puts "** VCAP CloudController = '#{@base_uri}' **\n\n"

    # Namespacing allows multiple tests to run in parallel.
    # Deprecated, along with the load-test tasks.
    # puts "** To run multiple tests in parallel, set environment variable VCAP_BVT_NS **"
    @namespace = ENV['VCAP_BVT_NS'] || ''
    puts "** Using namespace: '#{@namespace}' **\n\n" unless @namespace.empty?

    config_file = File.join(File.dirname(__FILE__), 'testconfig.yml')
    begin
      @config = File.open(config_file) do |f|
        YAML.load(f)
      end
    rescue => e
      puts "Could not read configuration file:  #{e}"
      exit
    end
    @testapps_dir = File.join(File.dirname(__FILE__), '../../apps')
    @client = VMC::BaseClient.new()

    # Make sure we cleanup if we had a failed run..
    # Fake out the login and registration piece..
    begin
      login
      @last_registered_user = test_user
    rescue
    end
    cleanup
  end

  def cleanup
    delete_app_internal(SIMPLE_APP)
    delete_app_internal(TINY_JAVA_APP)
    delete_app_internal(REDIS_LB_APP)
    delete_app_internal(ENV_TEST_APP)
    delete_app_internal(SIMPLE_DB_APP)
    delete_app_internal(SIMPLE_RACK_APP)
    delete_app_internal(BROKEN_APP)
    delete_app_internal(RAILS3_APP)
    delete_app_internal(JPA_APP)
    delete_app_internal(HIBERNATE_APP)
    delete_app_internal(DBRAILS_APP)
    delete_app_internal(DBRAILS_BROKEN_APP)
    delete_app_internal(GRAILS_APP)
    delete_app_internal(ROO_APP)
    delete_user
  end

  def create_uri name
    "#{name}.#{@suggest_url}"
  end

  def create_user
    @registered_user || "#{@namespace}#{TEST_AUTOMATION_USER_ID}"
  end

  def create_passwd
    @registered_user_passwd || TEST_AUTOMATION_PASSWORD
  end

  alias :test_user :create_user
  alias :test_passwd :create_passwd

  def delete_user
    unless @registered_user && @last_login_token && @last_registered_user
      if @last_registered_user
        @client.delete_user_internal(@base_uri, @last_registered_user, auth_hdr(@last_login_token))
      end
      @last_login_token = nil
      @last_registered_user = nil
    end
  end

  def get_registered_user
    @last_registered_user
  end

  def register
    unless @registered_user
      @client.register_internal(@base_uri, test_user, test_passwd)
    end
    @last_registered_user = test_user
  end

  def login
    token = @client.login_internal(@base_uri, test_user, test_passwd)
    # TBD - ABS: This is a hack around the 1 sec granularity of our token time stamp
    sleep(1)
    @last_login_token = token
  end

  def get_login_token
    @last_login_token
  end

  def list_apps token
    @client.get_apps_internal(@droplets_uri, auth_hdr(token))
  end

  def get_app_info app_list, app
    if app_list.empty?
      return
    end
    appname = get_app_name app
    app_list.each { |d|
      if d['name'] == appname
        return d
      end
    }
  end

  def create_app app, token, instances=1
    appname = get_app_name app
    delete_app app, token
    url = create_uri appname
    manifest = {
      :name => "#{appname}",
      :staging => {
        :model => @config[app]['framework'],
        :stack => @config[app]['startup']
      },
      :resources=> {
          :memory => @config[app]['memory'] || 64
      },
      :uris => [url],
      :instances => "#{instances}",
    }
    response = @client.create_app_internal @droplets_uri, manifest, auth_hdr(token)
    if response.status == 400
      puts "Creation of app #{appname} failed"
      return
    end
    app
  end

  def get_app_name app
    "#{@namespace}my_test_app_#{app}"
  end

  def upload_app app, token
    Dir.chdir("#{@testapps_dir}/#{app}")
    opt_war_file = nil
    if Dir.glob('*.war').first
      opt_war_file = Dir.glob('*.war').first
    end
    appname = get_app_name app
    @client.upload_app_bits @resources_uri, @droplets_uri, appname, auth_hdr(token), opt_war_file
  end

  def get_app_status app, token
    appname = get_app_name app
    response = @client.get_app_internal(@droplets_uri, appname, auth_hdr(token))
    if (response.status == 200)
      JSON.parse(response.content)
    end
  end

  def delete_app_internal app
    token = get_login_token
    if app != nil && token != nil
      delete_app app, token
    end
  end

  def delete_app app, token
    appname = get_app_name app
    response = @client.delete_app_internal(@droplets_uri, appname, [], auth_hdr(token))
    @app = nil
    response
  end

  def start_app app, token
    appname = get_app_name app
    app_manifest = get_app_status app, token
    if app_manifest == nil
     raise "Application #{appname} does not exist, app needs to be created."
    end

    if (app_manifest['state'] == 'STARTED')
      return
    end

    app_manifest['state'] = 'STARTED'
    response = @client.update_app_state_internal @droplets_uri, appname, app_manifest, auth_hdr(token)
    raise "Problem starting application #{appname}." if response.status != 200
  end

  def poll_until_done app, expected_health, token
    secs_til_timeout = @config['timeout_secs']
    health = nil
    sleep_time = 0.5
    while secs_til_timeout > 0 && health != expected_health
      sleep sleep_time
      secs_til_timeout = secs_til_timeout - sleep_time
      status = get_app_status app, token
      runningInstances = status['runningInstances'] || 0
      health = runningInstances/status['instances'].to_f
      # to mark? Not sure why this change, but breaks simple stop tests
      #health = runningInstances == 0 ? status['instances'].to_f : runningInstances.to_f
    end
    health
  end

  def stop_app app, token
    appname = get_app_name app
    app_manifest = get_app_status app, token
    if app_manifest == nil
     raise "Application #{appname} does not exist."
    end

    if (app_manifest['state'] == 'STOPPED')
      return
    end

    app_manifest['state'] = 'STOPPED'
    @client.update_app_state_internal @droplets_uri, appname, app_manifest, auth_hdr(token)
  end

  def get_app_files app, instance, path, token
    appname = get_app_name app
    @client.get_app_files_internal @droplets_uri, appname, instance, path, auth_hdr(token)
  end

  def get_instances_info app, token
    appname = get_app_name app
    instances_info = @client.get_app_instances_internal @droplets_uri, appname, auth_hdr(token)
    instances_info
  end

  def set_app_instances app, new_instance_count, token
    appname = get_app_name app
    app_manifest = get_app_status app, token
    if app_manifest == nil
      raise "App #{appname} needs to be deployed on AppCloud before being able to increment its instance count"
    end

    instances = app_manifest['instances']
    health = app_manifest['health']
    if (instances == new_instance_count)
      return
    end
    app_manifest['instances'] = new_instance_count


    response = @client.update_app_state_internal @droplets_uri, appname, app_manifest, auth_hdr(token)
    raise "Problem setting instance count for application #{appname}." if response.status != 200
    expected_health = 1.0
    poll_until_done app, expected_health, token
    new_instance_count
  end

  def get_app_crashes app, token
    appname = get_app_name app
    response = @client.get_app_crashes_internal @droplets_uri, appname, auth_hdr(token)

    crash_info = JSON.parse(response.content) if (response.status == 200)
  end

  def get_app_stats app, token
    appname = get_app_name app
    response = @client.get_app_stats_internal(@droplets_uri, appname, auth_hdr(token))
    if (response.status == 200)
      JSON.parse(response.content)
    end
  end

  def add_app_uri app, uri, token
    appname = get_app_name app
    app_manifest = get_app_status app, token
    if app_manifest == nil
     raise "Application #{appname} does not exist, app needs to be created."
    end

    app_manifest['uris'] << uri
    response = @client.update_app_state_internal @droplets_uri, appname, app_manifest, auth_hdr(token)
    raise "Problem adding uri #{uri} to application #{appname}." if response.status != 200
    expected_health = 1.0
    poll_until_done app, expected_health, token
  end

  def remove_app_uri app, uri, token
    appname = get_app_name app
    app_manifest = get_app_status app, token
    if app_manifest == nil
     raise "Application #{appname} does not exist, app needs to be created."
    end

    if app_manifest['uris'].delete(uri) == nil
      raise "Application #{appname} is not associated with #{uri} to be removed"
    end
    response = @client.update_app_state_internal @droplets_uri, appname, app_manifest, auth_hdr(token)
    raise "Problem removing uri #{uri} from application #{appname}." if response.status != 200
    expected_health = 1.0
    poll_until_done app, expected_health, token
  end

  def modify_and_upload_app app,token
    Dir.chdir("#{@testapps_dir}/modified_#{app}")
    appname = get_app_name app
    @client.upload_app_bits @resources_uri, @droplets_uri, appname, auth_hdr(token), nil
  end

  def modify_and_upload_bad_app app,token
    appname = get_app_name app
    Dir.chdir("#{@testapps_dir}/#{BROKEN_APP}")
    @client.upload_app_bits @resources_uri, @droplets_uri, appname, auth_hdr(token), nil
  end

  def poll_until_update_app_done app, token
    appname = get_app_name app
    @client.update_app_internal @droplets_uri, appname, auth_hdr(token)
    update_state = nil
    secs_til_timeout = @config['timeout_secs']
    while secs_til_timeout > 0 && update_state != 'SUCCEEDED' && update_state != 'CANARY_FAILED'
      sleep 1
      secs_til_timeout = secs_til_timeout - 1
      response = @client.get_update_app_status @droplets_uri, appname, auth_hdr(token)
      update_info = JSON.parse(response.content)
      update_state = update_info['state']
    end
    update_state
  end

  def get_services token
    response = HTTPClient.get "#{@base_uri}/info/services", nil, auth_hdr(token)
    services = JSON.parse(response.content)
    services
  end

  def provision_db_service token
    name = "#{@namespace}#{@app || 'simple_db_app'}"
    service_manifest = {
     :type=>"database",
     :vendor=>"mysql",
     :tier=>"free",
     :version=>"5.1.45",
     :name=>name,
     :options=>{"size"=>"256MiB"}}
     @client.add_service_internal @services_uri, service_manifest, auth_hdr(token)
    #puts "Provisioned service #{service_manifest}"
    service_manifest
  end

  def provision_redis_service token
    service_manifest = {
     :type=>"key-value",
     :vendor=>"redis",
     :tier=>"free",
     :version=>"5.1.45",
     :name=>"#{@namespace}redis_lb_app-service",
    }
    @client.add_service_internal @services_uri, service_manifest, auth_hdr(token)
    #puts "Provisioned service #{service_manifest}"
    service_manifest
  end

  def provision_redis_service_named token, name
    service_manifest = {
     :type=>"key-value",
     :vendor=>"redis",
     :tier=>"free",
     :version=>"5.1.45",
     :name=>redis_name(name),
    }
    @client.add_service_internal @services_uri, service_manifest, auth_hdr(token)
    #puts "Provisioned service #{service_manifest}"
    service_manifest
  end

  def redis_name name
    "#{@namespace}redis_#{name}"
  end

  def aurora_name name
    "#{@namespace}aurora_#{name}"
  end


  def mozyatmos_name name
    "#{@namespace}mozyatmos_#{name}"
  end

  def provision_aurora_service_named token, name
    service_manifest = {
     :type=>"database",
     :vendor=>"aurora",
     :tier=>"std",
     :name=>aurora_name(name),
    }
    @client.add_service_internal @services_uri, service_manifest, auth_hdr(token)
    #puts "Provisioned service #{service_manifest}"
    service_manifest
  end

  def provision_mozyatmos_service_named token, name
    service_manifest = {
     :type=>"blob",
     :vendor=>"mozyatmos",
     :tier=>"std",
     :name=>mozyatmos_name(name),
    }
    @client.add_service_internal @services_uri, service_manifest, auth_hdr(token)
    #puts "Provisioned service #{service_manifest}"
    service_manifest
  end


  def attach_provisioned_service app, service_manifest, token
    appname = get_app_name app
    app_manifest = get_app_status app, token
    provisioned_service = app_manifest['services']
    provisioned_service = [] unless provisioned_service
    svc_name = service_manifest[:name]
    provisioned_service << svc_name
    app_manifest['services'] = provisioned_service
    response = @client.update_app_state_internal @droplets_uri, appname, app_manifest, auth_hdr(token)
    raise "Problem attaching service #{svc_name} to application #{appname}." if response.status != 200
  end

  def delete_services services, token
    #puts "Deleting services #{services}"
    response = @client.delete_services_internal(@services_uri, services, auth_hdr(token))
    response
  end

  def get_uri app, relative_path=nil
    appname = get_app_name app
    uri = "#{appname}.#{@suggest_url}"
    if relative_path != nil
      uri << "/#{relative_path}"
    end
    uri
  end

  def get_app_contents app, relative_path=nil

    uri = get_uri app, relative_path
    get_uri_contents uri
  end

  def get_uri_contents uri
    easy = Curl::Easy.new
    easy.url = uri
    easy.http_get
    easy
  end

  def post_record uri, data_hash
    easy = Curl::Easy.new
    easy.url = uri
    easy.http_post(data_hash.to_json)
    easy.close
  end

  def put_record uri, data_hash
    easy = Curl::Easy.new
    easy.url = uri
    easy.http_put(data_hash.to_json)
    easy.close
  end

  def delete_record uri
    easy = Curl::Easy.new
    easy.url = uri
    easy.http_delete
    easy.close
  end

  def parse_json payload
    JSON.parse(payload)
  end

  def auth_hdr token
    {'AUTHORIZATION' => "#{token}"}
  end

end
