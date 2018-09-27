WindowCreate = function(w, ...)
  ret = world.WindowCreate(w, ...)
  CallPlugin("462b665ecb569efbf261422f", "registerMiniwindow", w)
  return ret
end
