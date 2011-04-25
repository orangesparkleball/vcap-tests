def dump_env(fmt)
  if fmt == 'html' || fmt == nil
    res = ''
    ENV.each do |k, v|
      res << "#{k}: #{v}<br/>"
    end
    res
  elsif fmt == 'json'
    res = {}
    ENV.each do |k, v|
      res[k] = v
    end
    puts res
    res.to_json
  end
end

run lambda{|env| [200, {"Content-Type" => 'text/html'}, dump_env('html')]}
