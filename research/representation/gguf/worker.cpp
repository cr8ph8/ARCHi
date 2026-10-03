// Request-owned, CPU-only, read-only GGUF activation observation.
// Upstream ABI: llama.cpp 161755f29e415e2c33efe906e91843c068efd664.
// Numerical coordinates are measurements, never correctness or safety labels.
#include "llama.h"
#include "ggml-backend.h"
#include "json.hpp"
#include <CommonCrypto/CommonDigest.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <unistd.h>

using json = nlohmann::json;
using Clock = std::chrono::steady_clock;
constexpr size_t MAX_REQUEST_BYTES = 8 * 1024 * 1024;
#ifndef ARCHI_GGUF_BACKEND
#define ARCHI_GGUF_BACKEND "llama.cpp:161755f29"
#endif
constexpr const char * BACKEND = ARCHI_GGUF_BACKEND;
constexpr const char * TEMPLATE = "<|im_start|>system\n{{system}}<|im_end|>\n<|im_start|>user\n{{input}}"
    "\n\nReturn exactly one JSON object matching this schema:\n{{schema}}"
    "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n";
static volatile sig_atomic_t cancelled = 0;
static void signal_cancel(int) { cancelled = 1; }
static void require(bool condition, const char * message) {
    if (!condition) throw std::runtime_error(message);
}
static std::string hex(const unsigned char * bytes, size_t n) {
    std::ostringstream out; out << std::hex << std::setfill('0');
    for (size_t i = 0; i < n; ++i) out << std::setw(2) << unsigned(bytes[i]);
    return out.str();
}
static std::string sha(const std::string & value) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(value.data(), static_cast<CC_LONG>(value.size()), bytes);
    return hex(bytes, sizeof(bytes));
}
static std::string string_field(const json & object, const char * key, size_t maximum = 256) {
    require(object.contains(key) && object[key].is_string(), "Missing string field");
    auto value = object[key].get<std::string>();
    require(!value.empty() && value.size() <= maximum && value.find('\0') == std::string::npos,
            "String length or embedded NUL is invalid");
    return value;
}
static void digest_field(const json & object, const char * key) {
    require(std::regex_match(string_field(object, key, 64), std::regex("[0-9a-f]{64}")),
            "Invalid SHA256 digest");
}
static void validate_compatibility_blob(const json & object) {
#ifdef ARCHI_QWEN35_BLOB
    require(string_field(object, "model_name") == "qwen3.5:9b" &&
            string_field(object, "model_blob_digest") == ARCHI_QWEN35_BLOB,
            "This text compatibility worker is restricted to the verified Ollama Qwen3.5:9b blob");
#endif
}
static int integer_field(const json & object, const char * key, int low, int high) {
    require(object.contains(key) && object[key].is_number_integer(), "Missing integer field");
    const auto n = object[key].get<int64_t>();
    require(n >= low && n <= high, "Integer exceeds worker limits");
    return static_cast<int>(n);
}
static std::vector<double> numbers(const json & value, size_t count, double bound = 1e6) {
    require(value.is_array() && value.size() == count, "Numeric array shape mismatch");
    std::vector<double> result; result.reserve(count);
    for (const auto & item : value) {
        require(item.is_number(), "Non-numeric array member");
        auto n = item.get<double>();
        require(std::isfinite(n) && std::abs(n) <= bound, "Invalid numeric array member");
        result.push_back(n);
    }
    return result;
}
static json parse_bounded(const std::string & data) {
    std::vector<std::set<std::string>> key_sets;
    return json::parse(data, [&](int depth, json::parse_event_t event, json & item) {
        require(depth <= 32, "JSON nesting exceeds limit");
        if (event == json::parse_event_t::object_start) {
            if (key_sets.size() <= static_cast<size_t>(depth)) key_sets.resize(depth + 1);
            key_sets[depth].clear();
        } else if (event == json::parse_event_t::key) {
            require(depth > 0 && key_sets[depth - 1].insert(item.get<std::string>()).second, "Duplicate JSON key");
        }
        return true;
    });
}
struct Request {
    json value, basis, identity;
    std::string prompt, path, layer, token_rule = "last";
    std::vector<double> direction, center;
    double offset = 0, scale = 1;
    int max_input = 0, max_output = 0, deadline_ms = 0, layer_index = 0;
    bool measure_record = false;
};
static Request validate(const json & object) {
    require(object.is_object(), "Request must be an object");
    validate_compatibility_blob(object);
    require(string_field(object, "schema") == "archi-gguf-shadow-request/v1", "Unknown request schema");
    require(string_field(object, "mode") == "shadow", "Only read-only shadow mode is supported");
    require(std::regex_match(string_field(object, "request_id"),
                            std::regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")),
            "Invalid request UUID");
    for (const char * name : {"role", "model_name"}) string_field(object, name);
    for (const char * key : {"model_digest", "model_blob_digest", "input_digest", "system_digest", "schema_digest", "prompt_digest",
                            "reader_artifact_digest", "basis_payload_digest"})
        digest_field(object, key);
    for (auto pair : {std::pair<const char *, const char *>{"input", "input_digest"}, {"system", "system_digest"},
                      {"response_schema", "schema_digest"}, {"prompt", "prompt_digest"}}) {
        require(object.contains(pair.first) && object[pair.first].is_string(), "Missing bound prompt component");
        auto data = object[pair.first].get<std::string>();
        require(data.size() <= 1024 * 1024 && data.find('\0') == std::string::npos, "Prompt component exceeds limit");
        require(sha(data) == object[pair.second].get<std::string>(), "Prompt component digest mismatch");
    }
    Request request; request.value = object;
    request.prompt = string_field(object, "prompt", 1024 * 1024);
    for (const char * key : {"input", "system", "response_schema"}) {
        require(object[key].get<std::string>().find("<|") == std::string::npos,
                "Bound components may not contain ChatML special-marker spellings");
    }
    const auto rendered = "<|im_start|>system\n" + object["system"].get<std::string>()
        + "<|im_end|>\n<|im_start|>user\n" + object["input"].get<std::string>()
        + "\n\nReturn exactly one JSON object matching this schema:\n" + object["response_schema"].get<std::string>()
        + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n";
    require(request.prompt == rendered, "Prompt does not match the bound template rendering");
    request.path = string_field(object, "model_path", 4096);
    require(request.path[0] == '/', "Model path must be absolute");
    request.max_input = integer_field(object, "max_input_tokens", 1, 8192);
    request.max_output = integer_field(object, "max_new_tokens", 1, 1024);
    request.deadline_ms = integer_field(object, "deadline_ms", 1, 180000);
    require(object.contains("basis") && object["basis"].is_object(), "Missing explicit reader basis");
    request.basis = object["basis"];
    const auto basis_payload = string_field(object, "basis_payload", 4 * 1024 * 1024);
    require(sha(basis_payload) == object["basis_payload_digest"].get<std::string>(), "Basis payload digest mismatch");
    require(parse_bounded(basis_payload) == request.basis, "Basis payload does not match supplied basis");
    const auto & basis = request.basis;
    for (const char * key : {"model_digest", "model_blob_digest", "tokenizer_digest", "template_digest",
                            "basis_digest", "reader_digest", "calibration_digest"}) digest_field(basis, key);
    require(basis["model_digest"] == object["model_digest"] && basis["model_blob_digest"] == object["model_blob_digest"],
            "Reader/model identity mismatch");
    require(basis["tokenizer_digest"] == object["model_blob_digest"], "GGUF tokenizer identity must bind whole model blob");
    require(basis["template_digest"] == sha(TEMPLATE), "Reader template identity mismatch");
    require(string_field(basis, "backend_revision") == BACKEND, "Reader backend revision mismatch");
    require(string_field(basis, "precision") == "Q4_K_M", "Only Q4_K_M reader/model identity is supported");
    if (basis.contains("token_rule")) request.token_rule = string_field(basis, "token_rule");
    require(request.token_rule == "last" || request.token_rule == "prompt-last", "Unsupported reader token rule");
    if (request.token_rule == "prompt-last")
        require(string_field(basis, "measurement_scope") == "synthetic-record-field-support/prompt-final/v1",
                "Prompt-only reader measurement scope mismatch");
    string_field(basis, "namespace");
    request.layer = string_field(basis, "layer");
    require(std::regex_match(request.layer, std::regex("l_out-[0-9]{1,3}")), "Unsupported tensor selector");
    request.layer_index = std::stoi(request.layer.substr(6));
    require(basis.contains("names") && basis["names"].is_array() && basis["names"].size() == 1 && basis["names"][0].is_string(),
            "Version one requires exactly one reader");
    const auto name = basis["names"][0].get<std::string>();
    require(!name.empty() && name.size() <= 128 && name.find('\0') == std::string::npos, "Invalid reader name");
    require(basis.contains("center") && basis["center"].is_array() && basis["center"].size() >= 1 && basis["center"].size() <= 32768,
            "Invalid hidden dimension");
    const size_t hidden = basis["center"].size();
    request.center = numbers(basis["center"], hidden);
    require(basis.contains("directions") && basis["directions"].is_array() && basis["directions"].size() == 1,
            "Version one requires one reader direction");
    request.direction = numbers(basis["directions"][0], hidden, 1.00001);
    double norm = 0;
    for (auto n : request.direction) norm += n*n;
    require(std::abs(norm - 1.0) <= 1e-5, "Reader direction must have unit norm");
    request.offset = numbers(basis.at("score_offset"), 1)[0];
    request.scale = numbers(basis.at("score_scale"), 1)[0];
    require(request.scale >= 1e-12, "Reader score scale must be positive");
    request.identity = basis;
    for (const char * key : {"directions", "center", "score_offset", "score_scale"}) request.identity.erase(key);
    json numeric = {{"directions", basis["directions"]}, {"center", basis["center"]},
                    {"score_offset", basis["score_offset"]}, {"score_scale", basis["score_scale"]}};
    request.identity["numeric_payload_digest"] = sha(numeric.dump());
    return request;
}
#include "task_assay.h"
struct Observation {
    const Request & request;
    Clock::time_point deadline;
    json samples = json::array();
    std::string error;
    bool capture = false;
    int decode_index = 0, token_position = 0, observed = 0;
    bool should_abort() const { return cancelled || Clock::now() >= deadline || !error.empty(); }
};
static bool abort_callback(void * user) { return static_cast<Observation *>(user)->should_abort(); }
static bool load_callback(float, void * user) { return !abort_callback(user); }
static bool eval_callback(ggml_tensor * tensor, bool ask, void * user) noexcept {
    auto & state = *static_cast<Observation *>(user);
    const bool selected = state.capture && state.request.layer == ggml_get_name(tensor);
    if (ask) return selected;
    if (state.should_abort()) return false;
    if (!selected) return true;
    try {
        require(++state.observed == 1, "Selected tensor was observed more than once per decode");
        const size_t hidden = state.request.center.size();
        require(tensor->type == GGML_TYPE_F32 && tensor->ne[0] == static_cast<int64_t>(hidden) && tensor->ne[1] >= 1 &&
                tensor->ne[2] == 1 && tensor->ne[3] == 1 && tensor->nb[0] == sizeof(float), "Unsupported activation tensor layout");
        const size_t offset = (static_cast<size_t>(tensor->ne[1]) - 1) * tensor->nb[1];
        require(offset <= ggml_nbytes(tensor) && hidden * sizeof(float) <= ggml_nbytes(tensor) - offset, "Activation slice exceeds tensor");
        std::vector<float> row(hidden);
        ggml_backend_tensor_get(tensor, row.data(), offset, row.size() * sizeof(float));
        double raw = 0;
        for (size_t i = 0; i < hidden; ++i) {
            require(std::isfinite(row[i]), "Non-finite activation sample");
            raw += (static_cast<double>(row[i]) - state.request.center[i]) * state.request.direction[i];
        }
        require(std::isfinite(raw), "Non-finite reader projection");
        const double z = (raw - state.request.offset) / state.request.scale;
        const double coordinate = z >= 0 ? 1.0/(1.0 + std::exp(-z)) : std::exp(z)/(1.0 + std::exp(z));
        require(std::isfinite(coordinate), "Non-finite coordinate");
        require(state.samples.size() < static_cast<size_t>(state.request.measure_record ? 1 : state.request.max_output), "Sample budget exceeded");
        state.samples.push_back({{"decode_index", state.decode_index}, {"token_position", state.token_position},
                                 {"layer", state.request.layer}, {"raw_scores", {raw}}, {"coordinates", {coordinate}}});
        std::fill(row.begin(), row.end(), 0.0f);
        return true;
    } catch (const std::exception & failure) { state.error = failure.what(); return false; }
}
template<typename State>
static std::string file_digest(int fd, State & state) {
    require(lseek(fd, 0, SEEK_SET) == 0, "Cannot seek GGUF file");
    CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx);
    std::array<char, 1024*1024> buffer;
    while (true) {
        require(!state.should_abort(), "Request cancelled or deadline exceeded while verifying model");
        const auto n = read(fd, buffer.data(), buffer.size());
        require(n >= 0, "Cannot read GGUF file");
        if (n == 0) break;
        CC_SHA256_Update(&ctx, buffer.data(), static_cast<CC_LONG>(n));
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest, &ctx);
    require(lseek(fd, 0, SEEK_SET) == 0, "Cannot rewind GGUF file");
    return hex(digest, sizeof(digest));
}
static json base_response(const Request & request) {
    json result = {{"schema", "archi-gguf-shadow-result/v1"}, {"mode", "shadow"}, {"basis", request.identity}};
    for (const char * key : {"request_id", "role", "model_name", "model_digest", "model_blob_digest", "input_digest",
                            "system_digest", "schema_digest", "prompt_digest", "reader_artifact_digest", "basis_payload_digest"}) result[key] = request.value[key];
    result["backend_revision"] = BACKEND;
    result["backend_execution"] = "arm64-cpu";
    return result;
}
static json run(const Request & request) {
    Observation state{request, Clock::now() + std::chrono::milliseconds(request.deadline_ms)};
    // A process-level deadline bounds model I/O and library code that lacks abort checkpoints.
    // The native owner also terminates this private child. No persistent server exists.
    std::atomic<bool> done{false};
    std::thread watchdog([&] {
        while (!done.load()) {
            if (Clock::now() > state.deadline + std::chrono::seconds(2)) _exit(124);
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
        }
    });
    struct Join { std::atomic<bool> & done; std::thread & thread; ~Join() { done.store(true); thread.join(); } } join{done, watchdog};
    const int fd = open(request.path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    require(fd >= 0, "Cannot open explicit GGUF model path");
    struct Close { int fd; ~Close() { close(fd); } } close_file{fd};
    struct stat before{}; require(fstat(fd, &before) == 0 && S_ISREG(before.st_mode), "Model must be a regular file");
    require(before.st_size >= 8 && before.st_size <= int64_t(32) * 1024 * 1024 * 1024, "Model file size outside limits");
    char magic[4]; require(read(fd, magic, 4) == 4 && std::memcmp(magic, "GGUF", 4) == 0, "Model is not GGUF");
    require(file_digest(fd, state) == request.value["model_blob_digest"].get<std::string>(), "Actual model blob digest mismatch");
    struct stat after{}; require(fstat(fd, &after) == 0 && before.st_size == after.st_size &&
            before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
            "Model changed during verification");
    FILE * file = fdopen(dup(fd), "rb"); require(file != nullptr, "Cannot open verified model stream");
    std::unique_ptr<FILE, decltype(&fclose)> owned_file(file, fclose);
    llama_log_set([](ggml_log_level, const char * text, void *) { std::fputs(text, stderr); }, nullptr);
    llama_backend_init();
    struct Backend { ~Backend() { llama_backend_free(); } } backend;
    auto parameters = llama_model_default_params();
    parameters.n_gpu_layers = 0;
    parameters.load_mode = LLAMA_LOAD_MODE_NONE;
    parameters.lazy_mode = LLAMA_LAZY_MODE_OFF;
    parameters.load_mtp = false;
    parameters.progress_callback = load_callback;
    parameters.progress_callback_user_data = &state;
    std::unique_ptr<llama_model, decltype(&llama_model_free)> model(llama_model_load_from_file_ptr(file, parameters), llama_model_free);
    require(model != nullptr, "GGUF model load failed or was cancelled");
    struct stat loaded{}; require(fstat(fd, &loaded) == 0 && before.st_size == loaded.st_size &&
            before.st_mtimespec.tv_sec == loaded.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec == loaded.st_mtimespec.tv_nsec,
            "Model changed while loading");
    require(!state.should_abort(), "Request cancelled or deadline exceeded");
    require(llama_model_n_embd(model.get()) == static_cast<int>(request.center.size()), "Model/reader hidden dimension mismatch");
    require(request.layer_index < llama_model_n_layer(model.get()), "Reader layer outside model");
    char architecture[128] = {}; llama_model_meta_val_str(model.get(), "general.architecture", architecture, sizeof(architecture));
    require(std::string(architecture) == "qwen3" || std::string(architecture) == "qwen35", "Only Qwen3/Qwen3.5 text models are supported");
    char file_type[32] = {}; llama_model_meta_val_str(model.get(), "general.file_type", file_type, sizeof(file_type));
    require(std::string(file_type) == "15", "Actual model precision is not Q4_K_M");
    const auto * vocab = llama_model_get_vocab(model.get());
    // Fully formatted prompts already contain their special markers. No implicit BOS or template.
    std::vector<llama_token> input(request.max_input + 1);
    int input_count = llama_tokenize(vocab, request.prompt.data(), static_cast<int32_t>(request.prompt.size()),
                                     input.data(), static_cast<int32_t>(input.size()), false, true);
    require(input_count > 0 && input_count <= request.max_input, "Prompt token count exceeds budget; no truncation performed");
    input.resize(input_count);
    auto context_parameters = llama_context_default_params();
    context_parameters.n_ctx = request.max_input + (request.measure_record ? 1 : request.max_output);
    context_parameters.n_batch = 256; context_parameters.n_ubatch = 256;
    context_parameters.n_seq_max = 1; context_parameters.n_threads = 4; context_parameters.n_threads_batch = 4;
    context_parameters.offload_kqv = false; context_parameters.op_offload = false;
    context_parameters.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED;
    context_parameters.cb_eval = eval_callback; context_parameters.cb_eval_user_data = &state;
    context_parameters.abort_callback = abort_callback; context_parameters.abort_callback_data = &state;
    std::unique_ptr<llama_context, decltype(&llama_free)> context(llama_init_from_model(model.get(), context_parameters), llama_free);
    require(context != nullptr, "Cannot allocate bounded inference context");
    auto decode = [&](llama_token * tokens, int n, bool capture, int position) {
        require(!state.should_abort(), "Request cancelled or deadline exceeded");
        state.capture = capture; state.token_position = position; state.observed = 0;
        const int status = llama_decode(context.get(), llama_batch_get_one(tokens, n));
        llama_synchronize(context.get());
        require(state.error.empty(), state.error.empty() ? "Activation callback failed" : state.error.c_str());
        require(status == 0 && !state.should_abort(), "Decode failed, cancelled, or exceeded deadline");
        if (capture) { require(state.observed == 1, "Selected activation was not observed"); ++state.decode_index; }
    };
    for (int start = 0; start < input_count; start += 256) {
        const int n = std::min(256, input_count - start);
        decode(input.data() + start, n, start + n == input_count, start + n - 1);
    }
    if (request.measure_record) {
        require(state.samples.size() == 1, "Record measurement requires exactly one prompt-final sample");
        const double raw = state.samples[0]["raw_scores"][0].get<double>();
        const double standardized = (raw - request.offset) / request.scale;
        require(std::isfinite(raw) && std::isfinite(standardized), "Non-finite record measurement");
        auto result = record_base_response(request);
        result.update({{"status", "ok"}, {"raw_score", raw}, {"standardized_score", standardized},
                       {"input_tokens", input_count}, {"output_tokens", 0}, {"token_position", input_count - 1}});
        return result;
    }
    std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)> sampler(llama_sampler_init_greedy(), llama_sampler_free);
    require(sampler != nullptr, "Cannot create deterministic sampler");
    std::string text, stop_reason = "token_limit";
    int output_count = 0;
    for (; output_count < request.max_output;) {
        require(!state.should_abort(), "Request cancelled or deadline exceeded");
        auto token = llama_sampler_sample(sampler.get(), context.get(), -1);
        if (llama_vocab_is_eog(vocab, token)) { stop_reason = "eos"; break; }
        std::array<char, 512> piece{};
        int n = llama_token_to_piece(vocab, token, piece.data(), static_cast<int>(piece.size()), 0, false);
        require(n >= 0 && n <= static_cast<int>(piece.size()), "Token text exceeds output piece bound");
        require(text.size() + n <= 65536, "Generated text exceeds byte budget");
        text.append(piece.data(), n); ++output_count;
        if (output_count < request.max_output) decode(&token, 1, request.token_rule == "last", input_count + output_count - 1);
    }
    json result = base_response(request);
    result.update({{"status", "ok"}, {"text", text}, {"output_digest", sha(text)}, {"stop_reason", stop_reason},
                   {"input_tokens", input_count}, {"output_tokens", output_count}, {"samples", state.samples}});
    return result;
}

// Explicit research-only acquisition. This route has a distinct schema and CLI;
// it never supplies raw tensors to the native shadow protocol above.
struct CalibrationRequest {
    json value;
    std::string path, layer;
    int layer_index = 0, max_input = 0, max_total = 0, deadline_ms = 0;
};
static CalibrationRequest validate_calibration(const json & object) {
    require(object.is_object(), "Calibration request must be an object");
    validate_compatibility_blob(object);
    require(string_field(object, "schema") == "archi-gguf-calibration-request/v1", "Unknown calibration schema");
    require(string_field(object, "purpose") == "synthetic-reader-calibration", "Unsupported acquisition purpose");
    require(object.contains("synthetic_only") && object["synthetic_only"].is_boolean() && object["synthetic_only"].get<bool>(),
            "Acquisition requires an explicit synthetic-only declaration");
    require(std::regex_match(string_field(object, "run_id"),
                            std::regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")),
            "Invalid calibration run UUID");
    const auto model_name = string_field(object, "model_name");
    require(model_name == "qwen3:8b" || model_name == "qwen3.5:9b", "Unsupported calibration model");
    for (const char * key : {"model_digest", "model_blob_digest", "tokenizer_digest", "template_digest",
                            "dataset_digest", "samples_payload_digest"}) digest_field(object, key);
    require(object["model_blob_digest"] == object["tokenizer_digest"], "Embedded tokenizer identity mismatch");
    require(object["template_digest"] == sha(TEMPLATE), "Calibration template identity mismatch");
    require(string_field(object, "backend_revision") == BACKEND, "Calibration backend revision mismatch");
    require(string_field(object, "precision") == "Q4_K_M", "Unsupported calibration precision");
    CalibrationRequest request; request.value = object;
    request.path = string_field(object, "model_path", 4096);
    require(request.path[0] == '/', "Calibration model path must be absolute");
    request.layer = string_field(object, "layer");
    require(std::regex_match(request.layer, std::regex("l_out-[0-9]{1,3}")), "Unsupported calibration tensor selector");
    request.layer_index = std::stoi(request.layer.substr(6));
    require(request.layer == "l_out-" + std::to_string(request.layer_index) && request.layer_index < 128,
            "Calibration tensor selector must be canonical and bounded");
    request.max_input = integer_field(object, "max_input_tokens", 1, 512);
    request.max_total = integer_field(object, "max_total_input_tokens", 1, 8192);
    request.deadline_ms = integer_field(object, "deadline_ms", 1, 540000);
    require(object.contains("samples") && object["samples"].is_array() && !object["samples"].empty() && object["samples"].size() <= 24,
            "Calibration requires one bounded batch of 1 to 24 synthetic samples");
    const auto payload = string_field(object, "samples_payload", 4 * 1024 * 1024);
    require(sha(payload) == object["samples_payload_digest"].get<std::string>(), "Calibration sample payload digest mismatch");
    require(parse_bounded(payload) == object["samples"], "Calibration sample payload mismatch");
    std::set<std::string> ids;
    for (const auto & sample : object["samples"]) {
        require(sample.is_object(), "Calibration sample must be an object");
        const auto id = string_field(sample, "sample_id", 128);
        require(ids.insert(id).second, "Duplicate calibration sample ID");
        for (auto pair : {std::pair<const char *, const char *>{"input", "input_digest"}, {"system", "system_digest"},
                          {"response_schema", "schema_digest"}, {"prompt", "prompt_digest"}}) {
            digest_field(sample, pair.second);
            require(sample.contains(pair.first) && sample[pair.first].is_string(), "Missing calibration prompt component");
            const auto component = sample[pair.first].get<std::string>();
            require(component.size() <= 16384 && component.find('\0') == std::string::npos, "Calibration prompt component exceeds bounds");
            require(sha(component) == sample[pair.second].get<std::string>(), "Calibration prompt component digest mismatch");
        }
        for (const char * key : {"input", "system", "response_schema"})
            require(sample[key].get<std::string>().find("<|") == std::string::npos, "Calibration component contains special-marker spelling");
        const auto rendered = "<|im_start|>system\n" + sample["system"].get<std::string>()
            + "<|im_end|>\n<|im_start|>user\n" + sample["input"].get<std::string>()
            + "\n\nReturn exactly one JSON object matching this schema:\n" + sample["response_schema"].get<std::string>()
            + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n";
        require(sample["prompt"] == rendered, "Calibration prompt does not match bound template");
    }
    return request;
}
static json calibration_base_response(const CalibrationRequest & request) {
    json result = {{"schema", "archi-gguf-calibration-result/v1"}, {"purpose", "synthetic-reader-calibration"},
                   {"synthetic_only", true}, {"backend_execution", "arm64-cpu"}, {"token_rule", "prompt-last"},
                   {"context_policy", "fresh-context-per-sample"}, {"generated_tokens", 0}};
    for (const char * key : {"run_id", "model_name", "model_digest", "model_blob_digest", "tokenizer_digest", "template_digest",
                            "backend_revision", "precision", "layer", "dataset_digest", "samples_payload_digest"}) result[key] = request.value[key];
    return result;
}
struct CalibrationObservation {
    const CalibrationRequest & request;
    Clock::time_point deadline;
    std::string error;
    std::vector<float> row;
    bool capture = false;
    int observed = 0;
    bool should_abort() const { return cancelled || Clock::now() >= deadline || !error.empty(); }
};
static bool calibration_abort_callback(void * user) { return static_cast<CalibrationObservation *>(user)->should_abort(); }
static bool calibration_load_callback(float, void * user) { return !calibration_abort_callback(user); }
static bool calibration_eval_callback(ggml_tensor * tensor, bool ask, void * user) noexcept {
    auto & state = *static_cast<CalibrationObservation *>(user);
    const bool selected = state.capture && state.request.layer == ggml_get_name(tensor);
    if (ask) return selected;
    if (state.should_abort()) return false;
    if (!selected) return true;
    try {
        require(++state.observed == 1, "Calibration tensor observed more than once");
        constexpr size_t hidden = 4096;
        require(tensor->type == GGML_TYPE_F32 && tensor->ne[0] == hidden && tensor->ne[1] >= 1 &&
                tensor->ne[2] == 1 && tensor->ne[3] == 1 && tensor->nb[0] == sizeof(float), "Unsupported calibration tensor layout");
        const size_t offset = (static_cast<size_t>(tensor->ne[1]) - 1) * tensor->nb[1];
        require(offset <= ggml_nbytes(tensor) && hidden * sizeof(float) <= ggml_nbytes(tensor) - offset,
                "Calibration activation slice exceeds tensor");
        state.row.resize(hidden);
        ggml_backend_tensor_get(tensor, state.row.data(), offset, hidden * sizeof(float));
        for (const auto value : state.row) require(std::isfinite(value), "Non-finite calibration activation");
        return true;
    } catch (const std::exception & failure) { state.error = failure.what(); return false; }
}
static json acquire_calibration(const CalibrationRequest & request) {
    CalibrationObservation state{request, Clock::now() + std::chrono::milliseconds(request.deadline_ms)};
    // These aggregate CPU limits apply only to this explicitly selected research route.
    // The soft limit asks our CPU abort callbacks to stop; the hard limit kills a stuck runtime.
    struct rlimit cpu_limit{2160, 2200};
    require(setrlimit(RLIMIT_CPU, &cpu_limit) == 0, "Cannot enforce calibration CPU budget");
    std::signal(SIGXCPU, signal_cancel);
    std::atomic<bool> done{false};
    std::thread watchdog([&] {
        while (!done.load()) {
            if (Clock::now() > state.deadline + std::chrono::seconds(2)) _exit(124);
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
        }
    });
    struct Join { std::atomic<bool> & done; std::thread & thread; ~Join() { done.store(true); thread.join(); } } join{done, watchdog};
    const int fd = open(request.path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    require(fd >= 0, "Cannot open explicit calibration GGUF path");
    struct Close { int fd; ~Close() { close(fd); } } close_file{fd};
    struct stat before{}; require(fstat(fd, &before) == 0 && S_ISREG(before.st_mode), "Calibration model must be a regular file");
    require(before.st_size >= 8 && before.st_size <= int64_t(32) * 1024 * 1024 * 1024, "Calibration model size outside limits");
    char magic[4]; require(read(fd, magic, 4) == 4 && std::memcmp(magic, "GGUF", 4) == 0, "Calibration model is not GGUF");
    require(file_digest(fd, state) == request.value["model_blob_digest"].get<std::string>(), "Calibration model blob digest mismatch");
    struct stat after{}; require(fstat(fd, &after) == 0 && before.st_size == after.st_size &&
            before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
            "Calibration model changed during verification");
    FILE * file = fdopen(dup(fd), "rb"); require(file != nullptr, "Cannot open verified calibration model stream");
    std::unique_ptr<FILE, decltype(&fclose)> owned_file(file, fclose);
    llama_log_set([](ggml_log_level, const char * text, void *) { std::fputs(text, stderr); }, nullptr);
    llama_backend_init();
    struct Backend { ~Backend() { llama_backend_free(); } } backend;
    auto parameters = llama_model_default_params();
    parameters.n_gpu_layers = 0; parameters.load_mode = LLAMA_LOAD_MODE_NONE;
    parameters.lazy_mode = LLAMA_LAZY_MODE_OFF; parameters.load_mtp = false;
    parameters.progress_callback = calibration_load_callback; parameters.progress_callback_user_data = &state;
    std::unique_ptr<llama_model, decltype(&llama_model_free)> model(llama_model_load_from_file_ptr(file, parameters), llama_model_free);
    require(model != nullptr, "Calibration model load failed or was cancelled");
    struct stat loaded{}; require(fstat(fd, &loaded) == 0 && before.st_size == loaded.st_size &&
            before.st_mtimespec.tv_sec == loaded.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec == loaded.st_mtimespec.tv_nsec,
            "Calibration model changed while loading");
    require(!state.should_abort(), "Calibration cancelled or deadline exceeded");
    require(llama_model_n_embd(model.get()) == 4096, "Unsupported calibration hidden dimension");
    require(request.layer_index < llama_model_n_layer(model.get()), "Calibration layer outside model");
    char architecture[128] = {}; llama_model_meta_val_str(model.get(), "general.architecture", architecture, sizeof(architecture));
    require(std::string(architecture) == "qwen3" || std::string(architecture) == "qwen35", "Unsupported calibration model architecture");
    char file_type[32] = {}; llama_model_meta_val_str(model.get(), "general.file_type", file_type, sizeof(file_type));
    require(std::string(file_type) == "15", "Actual calibration model precision is not Q4_K_M");
    const auto * vocab = llama_model_get_vocab(model.get());
    std::vector<std::vector<llama_token>> tokenized;
    int total_tokens = 0;
    // Bound the complete acquisition before any sample decode, with no truncation.
    for (const auto & sample : request.value["samples"]) {
        const auto prompt = sample["prompt"].get<std::string>();
        std::vector<llama_token> tokens(request.max_input + 1);
        const int count = llama_tokenize(vocab, prompt.data(), static_cast<int32_t>(prompt.size()),
                                        tokens.data(), static_cast<int32_t>(tokens.size()), false, true);
        require(count > 0 && count <= request.max_input, "Calibration sample exceeds token budget; no truncation performed");
        total_tokens += count;
        require(total_tokens <= request.max_total, "Calibration batch exceeds total token budget");
        tokens.resize(count); tokenized.push_back(std::move(tokens));
    }
    json samples = json::array();
    for (size_t index = 0; index < tokenized.size(); ++index) {
        require(!state.should_abort(), "Calibration cancelled or deadline exceeded");
        state.capture = false; state.observed = 0;
        std::fill(state.row.begin(), state.row.end(), 0.0f); state.row.clear();
        auto context_parameters = llama_context_default_params();
        context_parameters.n_ctx = request.max_input + 1;
        context_parameters.n_batch = 256; context_parameters.n_ubatch = 256;
        context_parameters.n_seq_max = 1; context_parameters.n_threads = 4; context_parameters.n_threads_batch = 4;
        context_parameters.offload_kqv = false; context_parameters.op_offload = false;
        context_parameters.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED;
        context_parameters.cb_eval = calibration_eval_callback; context_parameters.cb_eval_user_data = &state;
        context_parameters.abort_callback = calibration_abort_callback; context_parameters.abort_callback_data = &state;
        // Destruction at this loop iteration's end discards KV and recurrent state.
        std::unique_ptr<llama_context, decltype(&llama_free)> context(llama_init_from_model(model.get(), context_parameters), llama_free);
        require(context != nullptr, "Cannot allocate independent calibration context");
        auto & tokens = tokenized[index];
        for (int start = 0; start < static_cast<int>(tokens.size()); start += 256) {
            require(!state.should_abort(), "Calibration cancelled or deadline exceeded");
            const int count = std::min(256, static_cast<int>(tokens.size()) - start);
            state.capture = start + count == static_cast<int>(tokens.size());
            const int status = llama_decode(context.get(), llama_batch_get_one(tokens.data() + start, count));
            llama_synchronize(context.get());
            require(state.error.empty(), state.error.empty() ? "Calibration callback failed" : state.error.c_str());
            require(status == 0 && !state.should_abort(), "Calibration decode failed, cancelled, or exceeded budget");
        }
        require(state.observed == 1 && state.row.size() == 4096, "Calibration activation was not observed exactly once");
        const auto & input_sample = request.value["samples"][index];
        json sample = {{"token_position", tokens.size() - 1}, {"input_tokens", tokens.size()},
                       {"layer", request.layer}, {"activation", state.row}};
        for (const char * key : {"sample_id", "input_digest", "system_digest", "schema_digest", "prompt_digest"}) sample[key] = input_sample[key];
        samples.push_back(std::move(sample));
        std::fill(state.row.begin(), state.row.end(), 0.0f); state.row.clear();
        std::fprintf(stderr, "archi_calibration_progress completed=%zu total=%zu input_tokens=%zu\n",
                     index + 1, tokenized.size(), tokens.size());
        std::fflush(stderr);
    }
    json result = calibration_base_response(request);
    result.update({{"status", "ok"}, {"stop_reason", "all_samples_acquired"}, {"sample_count", samples.size()},
                   {"hidden_width", 4096}, {"total_input_tokens", total_tokens}, {"cpu_soft_limit_seconds", 2160},
                   {"cpu_hard_limit_seconds", 2200}, {"samples", samples}, {"activations_digest", sha(samples.dump())}});
    return result;
}
int main(int argc, char ** argv) {
    std::signal(SIGTERM, signal_cancel); std::signal(SIGINT, signal_cancel);
    // Parent termination remains the outer guard while stdin is still arriving.
    std::signal(SIGALRM, [](int) { _exit(124); }); alarm(185);
    const bool calibration = argc == 2 && (std::string(argv[1]) == "--acquire-calibration" || std::string(argv[1]) == "--validate-calibration");
    const bool record = argc == 2 && (std::string(argv[1]) == "--measure-record" || std::string(argv[1]) == "--validate-record");
    if (calibration) alarm(545);
    try {
        require(argc == 1 || (argc == 2 && std::string(argv[1]) == "--validate-only") || calibration || record, "Unknown worker argument");
        std::string data; data.reserve(65536); char buffer[16384];
        while (std::cin) {
            std::cin.read(buffer, sizeof(buffer)); const auto n = std::cin.gcount();
            require(data.size() + n <= (record ? 512 * 1024 : MAX_REQUEST_BYTES), "Request exceeds byte budget"); data.append(buffer, n);
        }
        // Reject duplicate keys instead of silently accepting last-value wins.
        auto parsed = parse_bounded(data);
        json response;
        if (record) {
            const auto request = validate_record(parsed);
            if (std::string(argv[1]) == "--validate-record") { response = record_base_response(request); response["status"] = "validated"; }
            else response = run(request);
        } else if (calibration) {
            const auto request = validate_calibration(parsed);
            if (std::string(argv[1]) == "--validate-calibration") { response = calibration_base_response(request); response["status"] = "validated"; }
            else response = acquire_calibration(request);
        } else {
            const Request request = validate(parsed);
            if (argc == 2) { response = base_response(request); response["status"] = "validated"; }
            else response = run(request);
        }
        std::cout << response.dump() << '\n'; return 0;
    } catch (const std::exception & failure) {
        std::cout << json({{"schema", record ? "archi-record-measurement-result/v1" : (calibration ? "archi-gguf-calibration-result/v1" : "archi-gguf-shadow-result/v1")}, {"status", "error"},
                           {"error", failure.what()}}).dump() << '\n';
        return 1;
    }
}
