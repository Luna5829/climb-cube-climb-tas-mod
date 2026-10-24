var keybinds
var line
var index = 0
var functions = {}
var background_functions = {}


func read(tas_file, keybinds_file):
    keybinds = JSON.parse_string(FileAccess.get_file_as_string(keybinds_file))

    # keybind validation
    for key in keybinds:
        key = key.to_lower()
        validate_keybind(key)

    var lines = FileAccess.get_file_as_string(tas_file).replace("\r", "").split("\n")

    var inputs = []
    var i = 0
    while i < lines.size():
        line = format_line(lines[i])

        if is_empty(line):
            i += 1
            continue

        i = parse_line(line, lines, i, inputs)

    return inputs


func validate_keybind(keybind):
    if keybind == "":
        push_error("Keybind cannot be empty")
        return false

    if keybind in ["goto", "repeat", "endrepeat", "endfunc"]:
        push_error("Keybind cannot be a reserved keyword: %s" % keybind)
        return false

    if keybind.ends_with("()"):
        push_error("Keybind cannot end with \"()\": %s" % keybind)
        return false

    return true


func validate_function_name(func_name):
    if func_name in functions:
        push_error("Function already defined: %s" % func_name)
        return false

    if func_name == "":
        push_error("Function name cannot be empty")
        return false

    if func_name in ["goto", "repeat", "endrepeat", "endfunc"]:
        push_error("Function name cannot be a reserved keyword: %s" % func_name)
        return false

    if func_name.ends_with("()"):
        push_error("Function name cannot end with \"()\": %s" % func_name)
        return false

    if func_name in keybinds:
        push_error("Function name cannot be the same as a keybind: %s" % func_name)
        return false

    return true


func parse_line(line, lines, i, inputs):
    var delimiter = ","
    if line.contains(" ") and not line.contains(","):
        delimiter = " "
    var parts = line.split(delimiter)

    # function definition
    if parts[0] == "func":
        var func_name = parts[1]
        if validate_function_name(func_name) == false:
            return i + 1
        var func_lines = []
        var new_index = collect_lines_until("endfunc", lines, i + 1)
        var function_lines = lines.slice(i + 1, new_index)
        var function_inputs = []
        var j = 0
        while j < function_lines.size():
            var func_line = format_line(function_lines[j])
            if not is_empty(func_line):
                j = parse_line(func_line, function_lines, j, function_inputs)
            else:
                j += 1
        functions[func_name] = function_inputs
        return new_index

    # direct function call
    if line.ends_with("()"):
        var func_name = line.substr(0, line.length() - 2)
        if not functions.has(func_name):
            push_error("Function not found: %s" % func_name)
            return i + 1

        var function_inputs = functions[func_name]
        for function_input in function_inputs:
            inputs.append(add_background_functions(function_input[0], function_input[1]))
        return i + 1

    # background function toggle
    if functions.has(parts[0]) and parts[1] in ["on", "off"]:
        var func_name = parts[0]
        var toggle = parts[1]

        if toggle == "on":
            var function_inputs = functions[func_name].map(func(func_input): return func_input[0])
            var function_lines = functions[func_name].map(func(func_input): return func_input[1])
            background_functions[func_name] = [0, function_inputs, function_lines]
        elif toggle == "off":
            if background_functions.has(func_name):
                background_functions.erase(func_name)
            else:
                push_error("Background function not found: %s" % func_name)

        return i + 1

    # repetition block
    if parts[0] == "repeat":
        var repeat_count = parts[1].to_int()
        var new_index = collect_lines_until("endrepeat", lines, i + 1)
        var repeat_lines = lines.slice(i + 1, new_index)

        for _k in range(repeat_count):
            var j = 0
            while j < repeat_lines.size():
                var repeat_line = format_line(repeat_lines[j])
                if not is_empty(repeat_line):
                    j = parse_line(repeat_line, repeat_lines, j, inputs)
                else:
                    j += 1

        return new_index

    parse_basic_input(line, parts, inputs)
    return i + 1


func parse_basic_input(line, parts, inputs):
    if parts[0] in ["print", "log"]:
        parts.pop_front()
        inputs.append([["NoInput", "print(%s)" % ",".join(parts)], line])
        return

    elif parts[0] == "pause":
        inputs.append([["NoInput", "pause"], line])
        return

    elif parts[0] == "savestate":
        var name = parts[1] if parts[1] else "savestate"
        inputs.append([["NoInput", "save_state(/%s.txt)" % name], line])
        return

    elif parts[0] == "loadstate":
        var name = parts[1] if parts[1] else "savestate"
        inputs.append([["NoInput", "load_state(/%s.txt)" % name], line])
        return

    elif parts[0] == "desynccheck":
        parts.pop_front()
        inputs.append([["NoInput", "desync_check(%s)" % ",".join(parts)], line])
        return

    elif parts[0] == "startrecording":
        inputs.append([["NoInput", "start_recording"], line])
        return

    elif parts[0] in ["endrecording", "stoprecording"]:
        var make_video = parts[1] != "false"
        inputs.append([["NoInput", "end_recording(%s)" % make_video], line])
        return

    var duration = parts[0].to_int()
    parts.remove_at(0)

    var frame_inputs = []
    index = 0
    while index < parts.size():
        process_inputs(parts, frame_inputs)
        index += 1

    if duration == 0:
        inputs.append([["InstantInput", frame_inputs], line])

    for i in range(duration):
        inputs.append(add_background_functions(frame_inputs, line))


func process_inputs(parts, frame_inputs):
    var input = parts[index]

    if input == "joystick":
        if parts[index + 2].is_valid_float():
            frame_inputs.append("joystick(%s,%s)" % [parts[index + 1], parts[index + 2]])
            index += 2
        else: # default force of 1
            frame_inputs.append("joystick(%s,1)" % parts[index + 1])
            index += 1
        return

    var input_key = keybinds[input]
    if input_key == null:
        push_error("Invalid input: %s" % input)
        return
    if input_key is not Array:
        input_key = [input_key]
    for key in input_key:
        frame_inputs.append(key)


# utils
func add_background_functions(inputs, line):
    if background_functions.is_empty():
        return [inputs, line]

    var new_inputs = inputs.duplicate()
    var new_line = "%s (" % line

    for func_name in background_functions:
        var func_data = background_functions[func_name]
        var frame_index = func_data[0]
        var function_input = func_data[1][frame_index % func_data[1].size()]
        var function_line = func_data[2][frame_index % func_data[2].size()]

        new_line += "%s, " % function_line
        new_inputs.append_array(function_input)
        func_data[0] += 1

    new_line = new_line.left(new_line.length() - 2) + ")"
    return [new_inputs, new_line]


func format_line(line):
    # remove comments
    var comment_index = line.find("#")
    if comment_index != -1:
        line = line.left(comment_index)

    line = line.strip_edges().to_lower()

    # collapse multiple spaces
    var regex = RegEx.new()
    regex.compile("\\s\\s+")
    line = regex.sub(line, "", true)

    return line


func is_empty(line):
    return line.is_empty() or line.begins_with("#")


func collect_lines_until(keyword, lines, i):
    var startIndex = i
    while i < lines.size() and not format_line(lines[i]).begins_with(keyword):
        i += 1
    return i
