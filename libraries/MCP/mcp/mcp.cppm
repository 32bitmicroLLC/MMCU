// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

module;

#include <cstddef>

export module mcp;

import stdio;

export namespace mmcu::mcp {

enum class json_type {
    invalid,
    null,
    boolean,
    number,
    string,
    object,
    array,
};

struct json_value {
    json_type type = json_type::invalid;
    const char* key = nullptr;
    std::size_t key_length = 0;
    const char* text = nullptr;
    std::size_t text_length = 0;
    long number = 0;
    bool boolean = false;
    std::size_t first_child = 0;
    std::size_t child_count = 0;
};

class json_document {
public:
    static constexpr std::size_t max_nodes = 48;

    bool parse(const char* source)
    {
        input_ = source;
        cursor_ = source;
        used_ = 0;
        root_index_ = 0;

        const auto root = parse_value(nullptr, 0);
        if (root == npos) {
            return false;
        }

        skip_ws();
        if (*cursor_ != '\0') {
            return false;
        }

        root_index_ = root;
        return true;
    }

    const json_value& root() const
    {
        return nodes_[root_index_];
    }

    const json_value* member(const json_value& object, const char* key) const
    {
        if (object.type != json_type::object) {
            return nullptr;
        }

        const auto key_length = cstring_length(key);
        for (std::size_t i = 0; i < object.child_count; ++i) {
            const auto& child = nodes_[object.first_child + i];
            if (equals(child.key, child.key_length, key, key_length)) {
                return &child;
            }
        }

        return nullptr;
    }

    bool string_equals(const json_value& value, const char* expected) const
    {
        return value.type == json_type::string
            && equals(value.text, value.text_length, expected, cstring_length(expected));
    }

    bool copy_string(const json_value& value, char* output, std::size_t capacity) const
    {
        if (value.type != json_type::string || capacity == 0) {
            return false;
        }

        const auto count = value.text_length < capacity - 1 ? value.text_length : capacity - 1;
        for (std::size_t i = 0; i < count; ++i) {
            output[i] = value.text[i];
        }
        output[count] = '\0';
        return true;
    }

    static std::size_t cstring_length(const char* text)
    {
        std::size_t length = 0;
        while (text[length] != '\0') {
            ++length;
        }
        return length;
    }

private:
    static constexpr std::size_t npos = static_cast<std::size_t>(-1);

    const char* input_ = nullptr;
    const char* cursor_ = nullptr;
    json_value nodes_[max_nodes]{};
    std::size_t used_ = 0;
    std::size_t root_index_ = 0;

    static bool equals(const char* left, std::size_t left_length, const char* right, std::size_t right_length)
    {
        if (left == nullptr || right == nullptr || left_length != right_length) {
            return false;
        }

        for (std::size_t i = 0; i < left_length; ++i) {
            if (left[i] != right[i]) {
                return false;
            }
        }

        return true;
    }

    std::size_t allocate(json_type type, const char* key, std::size_t key_length)
    {
        if (used_ >= max_nodes) {
            return npos;
        }

        const auto index = used_;
        ++used_;
        nodes_[index] = {};
        nodes_[index].type = type;
        nodes_[index].key = key;
        nodes_[index].key_length = key_length;
        return index;
    }

    void skip_ws()
    {
        while (*cursor_ == ' ' || *cursor_ == '\t' || *cursor_ == '\r' || *cursor_ == '\n') {
            ++cursor_;
        }
    }

    std::size_t parse_value(const char* key, std::size_t key_length)
    {
        skip_ws();

        if (*cursor_ == '{') {
            return parse_object(key, key_length);
        }
        if (*cursor_ == '[') {
            return parse_array(key, key_length);
        }
        if (*cursor_ == '"') {
            return parse_string_value(key, key_length);
        }
        if (*cursor_ == '-' || (*cursor_ >= '0' && *cursor_ <= '9')) {
            return parse_number_value(key, key_length);
        }
        if (match_literal("true")) {
            const auto index = allocate(json_type::boolean, key, key_length);
            if (index != npos) {
                nodes_[index].boolean = true;
            }
            return index;
        }
        if (match_literal("false")) {
            const auto index = allocate(json_type::boolean, key, key_length);
            if (index != npos) {
                nodes_[index].boolean = false;
            }
            return index;
        }
        if (match_literal("null")) {
            return allocate(json_type::null, key, key_length);
        }

        return npos;
    }

    bool match_literal(const char* literal)
    {
        const char* probe = cursor_;
        while (*literal != '\0') {
            if (*probe != *literal) {
                return false;
            }
            ++probe;
            ++literal;
        }
        cursor_ = probe;
        return true;
    }

    bool parse_string_span(const char*& begin, std::size_t& length)
    {
        if (*cursor_ != '"') {
            return false;
        }

        ++cursor_;
        begin = cursor_;
        length = 0;

        while (*cursor_ != '\0' && *cursor_ != '"') {
            if (*cursor_ == '\\' && cursor_[1] != '\0') {
                ++cursor_;
            }
            ++cursor_;
            ++length;
        }

        if (*cursor_ != '"') {
            return false;
        }

        ++cursor_;
        return true;
    }

    std::size_t parse_string_value(const char* key, std::size_t key_length)
    {
        const char* begin = nullptr;
        std::size_t length = 0;
        if (!parse_string_span(begin, length)) {
            return npos;
        }

        const auto index = allocate(json_type::string, key, key_length);
        if (index != npos) {
            nodes_[index].text = begin;
            nodes_[index].text_length = length;
        }
        return index;
    }

    std::size_t parse_number_value(const char* key, std::size_t key_length)
    {
        const bool negative = *cursor_ == '-';
        if (negative) {
            ++cursor_;
        }

        long value = 0;
        if (*cursor_ < '0' || *cursor_ > '9') {
            return npos;
        }

        while (*cursor_ >= '0' && *cursor_ <= '9') {
            value = (value * 10) + static_cast<long>(*cursor_ - '0');
            ++cursor_;
        }

        const auto index = allocate(json_type::number, key, key_length);
        if (index != npos) {
            nodes_[index].number = negative ? -value : value;
        }
        return index;
    }

    std::size_t parse_object(const char* key, std::size_t key_length)
    {
        const auto object = allocate(json_type::object, key, key_length);
        if (object == npos) {
            return npos;
        }

        ++cursor_;
        skip_ws();

        if (*cursor_ == '}') {
            ++cursor_;
            return object;
        }

        nodes_[object].first_child = used_;

        for (;;) {
            const char* child_key = nullptr;
            std::size_t child_key_length = 0;
            if (!parse_string_span(child_key, child_key_length)) {
                return npos;
            }

            skip_ws();
            if (*cursor_ != ':') {
                return npos;
            }
            ++cursor_;

            const auto child = parse_value(child_key, child_key_length);
            if (child == npos) {
                return npos;
            }
            ++nodes_[object].child_count;

            skip_ws();
            if (*cursor_ == '}') {
                ++cursor_;
                return object;
            }
            if (*cursor_ != ',') {
                return npos;
            }
            ++cursor_;
        }
    }

    std::size_t parse_array(const char* key, std::size_t key_length)
    {
        const auto array = allocate(json_type::array, key, key_length);
        if (array == npos) {
            return npos;
        }

        ++cursor_;
        skip_ws();

        if (*cursor_ == ']') {
            ++cursor_;
            return array;
        }

        nodes_[array].first_child = used_;

        for (;;) {
            const auto child = parse_value(nullptr, 0);
            if (child == npos) {
                return npos;
            }
            ++nodes_[array].child_count;

            skip_ws();
            if (*cursor_ == ']') {
                ++cursor_;
                return array;
            }
            if (*cursor_ != ',') {
                return npos;
            }
            ++cursor_;
        }
    }
};

struct tool_result {
    const char* text = "";
    bool is_error = false;
};

inline tool_result tool_text_result(const char* text, bool is_error = false)
{
    return {
        .text = text,
        .is_error = is_error,
    };
}

using tool_handler = tool_result (*)(const json_document& document, const json_value& arguments);

struct tool_definition {
    const char* name = nullptr;
    const char* description = nullptr;
    const char* input_schema = nullptr;
    tool_handler handler = nullptr;
};

template<std::size_t MaxTools = 8, std::size_t LineCapacity = 1024>
class server {
public:
    explicit constexpr server(mmcu::stdio::transport io = mmcu::stdio::default_transport) :
        io_(io)
    {
    }

    bool register_tool(
        const char* name,
        tool_handler handler,
        const char* description = "",
        const char* input_schema = "{\"type\":\"object\"}"
    )
    {
        if (tool_count_ >= MaxTools || name == nullptr || handler == nullptr) {
            return false;
        }

        tools_[tool_count_] = {
            .name = name,
            .description = description,
            .input_schema = input_schema,
            .handler = handler,
        };
        ++tool_count_;
        return true;
    }

    void run()
    {
        char line[LineCapacity]{};
        std::size_t length = 0;
        for (;;) {
            if (!io_.read_line(line, LineCapacity, length) || length == 0) {
                continue;
            }
            process_line(line);
        }
    }

    bool process_line(const char* line)
    {
        json_document document;
        if (!document.parse(line)) {
            write_error(nullptr, -32700, "Parse error");
            return false;
        }

        const auto& root = document.root();
        if (root.type != json_type::object) {
            write_error(nullptr, -32600, "Invalid Request");
            return false;
        }

        const auto* jsonrpc = document.member(root, "jsonrpc");
        const auto* method = document.member(root, "method");
        const auto* id = document.member(root, "id");

        if (jsonrpc == nullptr || method == nullptr || !document.string_equals(*jsonrpc, "2.0") || method->type != json_type::string) {
            write_error(id, -32600, "Invalid Request");
            return false;
        }

        const bool notification = id == nullptr;
        if (document.string_equals(*method, "initialize")) {
            if (!notification) {
                write_initialize_response(id);
            }
            return true;
        }

        if (document.string_equals(*method, "notifications/initialized")) {
            return true;
        }

        if (document.string_equals(*method, "tools/list")) {
            if (!notification) {
                write_tools_list_response(id);
            }
            return true;
        }

        if (document.string_equals(*method, "tools/call")) {
            const auto* params = document.member(root, "params");
            const auto* name = params == nullptr ? nullptr : document.member(*params, "name");
            const auto* arguments = params == nullptr ? nullptr : document.member(*params, "arguments");

            if (params == nullptr || name == nullptr || name->type != json_type::string) {
                if (!notification) {
                    write_error(id, -32602, "Invalid params");
                }
                return false;
            }

            const auto* tool = find_tool(document, *name);
            if (tool == nullptr) {
                if (!notification) {
                    write_error(id, -32601, "Tool not found");
                }
                return false;
            }

            const auto empty_arguments = json_value{.type = json_type::object};
            const auto& call_arguments = arguments == nullptr ? empty_arguments : *arguments;
            const auto result = tool->handler(document, call_arguments);
            if (!notification) {
                write_tool_result(id, result);
            }
            return !result.is_error;
        }

        if (!notification) {
            write_error(id, -32601, "Method not found");
        }
        return false;
    }

private:
    mmcu::stdio::transport io_;
    tool_definition tools_[MaxTools]{};
    std::size_t tool_count_ = 0;

    const tool_definition* find_tool(const json_document& document, const json_value& name) const
    {
        for (std::size_t i = 0; i < tool_count_; ++i) {
            if (document.string_equals(name, tools_[i].name)) {
                return &tools_[i];
            }
        }
        return nullptr;
    }

    void write_json_string(const char* text) const
    {
        io_.write_byte('"');
        while (*text != '\0') {
            if (*text == '"' || *text == '\\') {
                io_.write_byte('\\');
            }
            io_.write_byte(*text);
            ++text;
        }
        io_.write_byte('"');
    }

    void write_json_string(const char* text, std::size_t length) const
    {
        io_.write_byte('"');
        for (std::size_t i = 0; i < length; ++i) {
            if (text[i] == '"' || text[i] == '\\') {
                io_.write_byte('\\');
            }
            io_.write_byte(text[i]);
        }
        io_.write_byte('"');
    }

    void write_id(const json_value* id) const
    {
        if (id == nullptr || id->type == json_type::null) {
            io_.write_string("null");
        } else if (id->type == json_type::string) {
            write_json_string(id->text, id->text_length);
        } else if (id->type == json_type::number) {
            write_integer(id->number);
        } else {
            io_.write_string("null");
        }
    }

    void write_integer(long value) const
    {
        char buffer[24]{};
        auto cursor = sizeof(buffer);
        const bool negative = value < 0;
        unsigned long magnitude = negative ? static_cast<unsigned long>(-value) : static_cast<unsigned long>(value);

        do {
            --cursor;
            buffer[cursor] = static_cast<char>('0' + (magnitude % 10));
            magnitude /= 10;
        } while (magnitude != 0);

        if (negative) {
            --cursor;
            buffer[cursor] = '-';
        }

        io_.write_string(&buffer[cursor]);
    }

    void write_error(const json_value* id, int code, const char* message) const
    {
        io_.write_string("{\"jsonrpc\":\"2.0\",\"id\":");
        write_id(id);
        io_.write_string(",\"error\":{\"code\":");
        write_integer(code);
        io_.write_string(",\"message\":");
        write_json_string(message);
        io_.write_string("}}\n");
        io_.flush();
    }

    void write_initialize_response(const json_value* id) const
    {
        io_.write_string("{\"jsonrpc\":\"2.0\",\"id\":");
        write_id(id);
        io_.write_string(",\"result\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"mmcu\",\"version\":\"0.1.0\"}}}\n");
        io_.flush();
    }

    void write_tools_list_response(const json_value* id) const
    {
        io_.write_string("{\"jsonrpc\":\"2.0\",\"id\":");
        write_id(id);
        io_.write_string(",\"result\":{\"tools\":[");
        for (std::size_t i = 0; i < tool_count_; ++i) {
            if (i != 0) {
                io_.write_byte(',');
            }
            io_.write_string("{\"name\":");
            write_json_string(tools_[i].name);
            io_.write_string(",\"description\":");
            write_json_string(tools_[i].description == nullptr ? "" : tools_[i].description);
            io_.write_string(",\"inputSchema\":");
            io_.write_string(tools_[i].input_schema == nullptr ? "{\"type\":\"object\"}" : tools_[i].input_schema);
            io_.write_byte('}');
        }
        io_.write_string("]}}\n");
        io_.flush();
    }

    void write_tool_result(const json_value* id, tool_result result) const
    {
        io_.write_string("{\"jsonrpc\":\"2.0\",\"id\":");
        write_id(id);
        io_.write_string(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
        write_json_string(result.text == nullptr ? "" : result.text);
        io_.write_string("}],\"isError\":");
        io_.write_string(result.is_error ? "true" : "false");
        io_.write_string("}}\n");
        io_.flush();
    }
};

}
