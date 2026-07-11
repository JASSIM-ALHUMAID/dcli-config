function Linemode:size_and_mtime()
	local time = math.floor(self._file.cha.mtime or 0)
	if time == 0 then
		time = ""
	elseif os.date("%Y", time) == os.date("%Y") then
		time = os.date("%b %d %H:%M", time)
	else
		time = os.date("%b %d  %Y", time)
	end

	local size = self._file:size()
	if not size then
		local folder = cx.active:history(self._file.url)
		size = folder and tostring(#folder.files) or ""
	else
		size = ya.readable_size(size)
	end
	return string.format("%s %s", size, time)
end
