// Scalar-only, single-prefill record measurements. This protocol does not
// change the pinned text graph, model weights, or existing shadow/calibration APIs.
#pragma once

namespace record_assay {
constexpr const char * BACKEND_REVISION = "llama.cpp:161755f29+archi-qwen35-text-v1";
constexpr const char * MODEL = "6488c96fa5faab64bb65cbd30d4289e20e6130ef535a93ef9a49f42eda893ea7";
constexpr const char * BLOB = "dec52a44569a2a25341c4e4d3fee25846eed4f6f0b936278e3a3c900bb99d37c";
constexpr const char * READER = "b699deda8bc7bdd99b5e362c88d16accdd66c163222e89647086b44a680a7ac0";
constexpr const char * NUMERIC = "3cd3b593f393d252eef9d63f8090a685a52e0ce3c37f94f778ad0ccea0515bef";
constexpr const char * CANDIDATE = "e2e2beed1097fe8d8655242ffe51c26469e4ed77349ba77c04f14b166a0b6bd3";
constexpr const char * QUALIFICATION = "f382bbae7192a14aa5b32c42e6630667c8e7b547c50092b2ef2efa162c908838";
constexpr const char * PLAN = "8db6b8144b00b856e3084335393394484c790124c5bb731f91de84e7a75de3bc";
constexpr const char * SCOPE = "synthetic-record-field-support/prompt-final/ridge-v1";

static void exact_keys(const json & value, const std::set<std::string> & expected) {
    require(value.is_object() && value.size() == expected.size(), "Unexpected record protocol fields");
    for (auto it = value.begin(); it != value.end(); ++it)
        require(expected.count(it.key()) == 1, "Unexpected record protocol field");
}
static std::string numeric_digest(const Request & request) {
    static_assert(sizeof(double) == 8, "Float64 protocol requires eight-byte doubles");
    std::string bytes = "archi-reader-numerics/v1\n";
    auto append = [&](double value) {
        uint64_t bits; std::memcpy(&bits, &value, sizeof(bits));
        for (int i = 0; i < 8; ++i) bytes.push_back(static_cast<char>((bits >> (8 * i)) & 255));
    };
    for (double value : request.direction) append(value);
    for (double value : request.center) append(value);
    append(request.offset); append(request.scale);
    return sha(bytes);
}
static void validate_input(const std::string & input) {
    const std::set<std::string> fields = {"location", "owner", "deadline", "color", "material", "status",
        "destination", "size", "quantity", "category", "label", "priority"};
    const auto split = input.rfind("\n\nWhich ");
    require(split != std::string::npos, "Record input requires the exact lookup question");
    const auto question = input.substr(split + 2);
    std::smatch query;
    require(std::regex_match(question, query, std::regex("Which ([a-z]+) is listed for ([A-Za-z][A-Za-z0-9_-]{0,31})\\?")) &&
            fields.count(query[1].str()) == 1, "Record query is outside the bounded lookup task");
    std::istringstream stream(input.substr(0, split));
    std::string line; std::getline(stream, line);
    require(line == "record | field | value", "Record table header mismatch");
    std::set<std::string> ids, pairs;
    size_t count = 0;
    while (std::getline(stream, line)) {
        std::smatch row;
        require(++count <= 24 && std::regex_match(line, row,
            std::regex("([A-Za-z][A-Za-z0-9_-]{0,31}) \\| ([a-z]+) \\| ([ -~]{1,96})")), "Malformed bounded record row");
        const auto id = row[1].str(), field = row[2].str(), value = row[3].str();
        require(fields.count(field) == 1 && value.front() != ' ' && value.back() != ' ' &&
                value.find('|') == std::string::npos && value.find('=') == std::string::npos &&
                pairs.insert(id + "\n" + field).second, "Invalid or repeated record field");
        ids.insert(id);
        require(ids.size() <= 2, "Record task permits exactly two record IDs");
    }
    require(count >= 2 && ids.size() == 2 && ids.count(query[2].str()) == 1,
            "Record task requires two records and a query for one of them");
}
}

static Request validate_record(const json & object) {
    using namespace record_assay;
    exact_keys(object, {"schema", "request_id", "model_name", "model_digest", "model_blob_digest", "model_path",
        "backend_revision", "reader_artifact_digest", "numeric_digest", "candidate_digest", "qualification_digest", "plan_digest",
        "tokenizer_digest", "template_digest", "precision", "layer", "token_rule", "measurement_scope",
        "input", "system", "response_schema", "prompt", "input_digest", "system_digest", "schema_digest", "prompt_digest",
        "max_input_tokens", "max_new_tokens", "deadline_ms", "basis"});
    require(string_field(object, "schema") == "archi-record-measurement-request/v1", "Unknown record measurement schema");
    require(std::string(BACKEND) == BACKEND_REVISION && string_field(object, "backend_revision") == BACKEND_REVISION,
            "Record measurement requires the pinned text adapter");
    validate_compatibility_blob(object);
    require(string_field(object, "model_name") == "qwen3.5:9b", "Record model mismatch");
    require(std::regex_match(string_field(object, "request_id"),
        std::regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")), "Invalid record request UUID");
    for (auto pin : {std::pair<const char *, const char *>{"model_digest", MODEL}, {"model_blob_digest", BLOB},
                    {"tokenizer_digest", BLOB}, {"reader_artifact_digest", READER}, {"numeric_digest", NUMERIC},
                    {"candidate_digest", CANDIDATE}, {"qualification_digest", QUALIFICATION}, {"plan_digest", PLAN}}) {
        digest_field(object, pin.first);
        require(object[pin.first] == pin.second, "Record reader identity mismatch");
    }
    digest_field(object, "template_digest");
    require(object["template_digest"] == sha(TEMPLATE), "Record template identity mismatch");
    require(string_field(object, "precision") == "Q4_K_M" && string_field(object, "layer") == "l_out-31" &&
            string_field(object, "token_rule") == "prompt-last" && string_field(object, "measurement_scope") == SCOPE,
            "Record measurement scope mismatch");
    Request request; request.value = object; request.measure_record = true;
    request.path = string_field(object, "model_path", 4096);
    require(request.path[0] == '/', "Record model path must be absolute");
    request.max_input = integer_field(object, "max_input_tokens", 512, 512);
    request.max_output = integer_field(object, "max_new_tokens", 0, 0);
    request.deadline_ms = integer_field(object, "deadline_ms", 180000, 180000);
    request.layer = "l_out-31"; request.layer_index = 31; request.token_rule = "prompt-last";
    for (auto pair : {std::pair<const char *, const char *>{"input", "input_digest"}, {"system", "system_digest"},
                     {"response_schema", "schema_digest"}, {"prompt", "prompt_digest"}}) {
        const auto component = string_field(object, pair.first, std::string(pair.first) == "prompt" ? 32768 : 8192);
        digest_field(object, pair.second);
        require(sha(component) == object[pair.second].get<std::string>(), "Record component digest mismatch");
        if (std::string(pair.first) != "prompt") {
            require(component.find("<|") == std::string::npos && component.find("|>") == std::string::npos &&
                    component.find("<think>") == std::string::npos && component.find("</think>") == std::string::npos,
                    "Record component contains a special delimiter");
        }
    }
    request.prompt = object["prompt"].get<std::string>();
    const auto rendered = "<|im_start|>system\n" + object["system"].get<std::string>()
        + "<|im_end|>\n<|im_start|>user\n" + object["input"].get<std::string>()
        + "\n\nReturn exactly one JSON object matching this schema:\n" + object["response_schema"].get<std::string>()
        + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n";
    require(request.prompt == rendered, "Record prompt does not match bound rendering");
    const json answer_schema = {{"type", "object"}, {"properties", {{"answer", {{"type", "string"}}}}},
                                {"required", {"answer"}}, {"additionalProperties", false}};
    require(parse_bounded(object["response_schema"].get<std::string>()) == answer_schema, "Record answer schema mismatch");
    require(object["system"] == "Read the supplied project records. Answer only the exact record and field asked for. "
        "Use only those records. If that field is absent for that record, answer NEED_SOURCE. Return one JSON object.",
        "Record system instruction is outside the fixed lookup task");
    validate_input(object["input"].get<std::string>());
    request.basis = object["basis"];
    exact_keys(request.basis, {"directions", "center", "score_offset", "score_scale"});
    require(request.basis["directions"].is_array() && request.basis["directions"].size() == 1,
            "Record reader requires exactly one direction");
    request.direction = numbers(request.basis["directions"][0], 4096, 1.00001);
    request.center = numbers(request.basis["center"], 4096);
    request.offset = numbers(request.basis["score_offset"], 1)[0];
    request.scale = numbers(request.basis["score_scale"], 1)[0];
    require(request.scale >= 1e-12, "Record scale must be positive");
    require(numeric_digest(request) == NUMERIC, "Record numerical weights do not match the qualified reader");
    return request;
}

static json record_base_response(const Request & request) {
    json result = {{"schema", "archi-record-measurement-result/v1"}, {"backend_execution", "arm64-cpu"}};
    for (const char * key : {"request_id", "model_name", "model_digest", "model_blob_digest", "backend_revision",
                           "reader_artifact_digest", "numeric_digest", "candidate_digest", "qualification_digest", "plan_digest",
                           "tokenizer_digest", "template_digest", "precision", "layer", "token_rule", "measurement_scope",
                           "input_digest", "system_digest", "schema_digest", "prompt_digest"}) result[key] = request.value[key];
    return result;
}
