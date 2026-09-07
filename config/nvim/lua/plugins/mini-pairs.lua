-- 调整 mini.pairs 的两个默认行为：
-- 1) 输入 ) ] } 时直接插入字符，不再"跳过"右侧已有的同类括号
-- 2) <BS> 删除 ( [ { 时只删单个字符，不再成对删除对应的右括号
-- （输入 ( [ { 仍会自动补全右括号；引号行为不变）
return {
  "nvim-mini/mini.pairs",
  opts = {
    mappings = {
      -- 关闭"跳过右括号"：取消 ) ] } 的映射，恢复原生插入行为
      [")"] = false,
      ["]"] = false,
      ["}"] = false,
      -- 关闭 <BS> 成对删除：保留自动补全，但不再注册给 bs
      ["("] = { register = { bs = false } },
      ["["] = { register = { bs = false } },
      ["{"] = { register = { bs = false } },
    },
  },
}
