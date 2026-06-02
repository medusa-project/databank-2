module IdbConfig
  module_function

  def dig(*keys)
    IDB_CONFIG.dig(*keys)
  end

  def fetch(*keys, default: nil)
    value = dig(*keys)
    value.nil? ? default : value
  end
end
