outName=export.zip
rm -v $outName

if 7z a -xr@7z_build_exclude.txt export.zip; then
	echo "Build Done"
else
	echo "Build Failed! ==========="
fi

read

