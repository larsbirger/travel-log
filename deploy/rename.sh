old_name="app"
new_name="travel-log"

if [ -n "$old_name" ] && [ -n "$new_name" ]; then
    for file in deploy/"$old_name".*; do
        if [ -e "$file" ]; then
            mv "$file" "${file/$old_name./$new_name.}"
        fi
    done
else
    echo "❌ Error: Both old_name and new_name must be filled out!"
fi