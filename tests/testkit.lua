-- Tiny test framework. Usage: T.test(name, fn); assertions T.eq/T.ok.
local T = { passed = 0, failed = 0 }

function T.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    T.passed = T.passed + 1
    print("PASS  " .. name)
  else
    T.failed = T.failed + 1
    print("FAIL  " .. name .. "\n      " .. tostring(err))
  end
end

function T.eq(got, want, msg)
  if got ~= want then
    error((msg or "eq") .. ": got " .. tostring(got) .. ", want " .. tostring(want), 2)
  end
end

function T.ok(v, msg)
  if not v then error(msg or "expected truthy", 2) end
end

function T.finish()
  print(string.format("== %d passed, %d failed ==", T.passed, T.failed))
  return T.failed == 0 and 0 or 1
end

return T
