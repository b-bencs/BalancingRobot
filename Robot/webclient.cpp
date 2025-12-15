#ifndef WEBCLIENT_CPP
#define WEBCLIENT_CPP

#include <string>
#include <stdexcept>
#include <curl/curl.h>

class WebClient {
    std::string url;
    std::string response;

    static size_t WriteCallback(char* ptr, size_t size, size_t nmemb, void* userdata) {
        size_t total = size * nmemb;
        auto* self = static_cast<WebClient*>(userdata);
        self->response.append(ptr, total);
        return total;
    }

public:
    explicit WebClient(const std::string& url) : url(url), response() {}

    void post(const std::string& body) {
        CURL* curl = curl_easy_init();
        if (!curl) {
            throw std::runtime_error("curl_easy_init failed");
        }

        response.clear();

        struct curl_slist* headers = nullptr;
        headers = curl_slist_append(headers, "Content-Type: application/json");

        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_POST, 1L);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, body.size());
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, &WebClient::WriteCallback);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, this);

        CURLcode res = curl_easy_perform(curl);
        if (res != CURLE_OK) {
            curl_slist_free_all(headers);
            curl_easy_cleanup(curl);
            throw std::runtime_error(
                std::string("curl_easy_perform failed: ") + curl_easy_strerror(res));
        }

        long http_code = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);

        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);

        if (http_code / 100 != 2) {
            throw std::runtime_error("HTTP status " + std::to_string(http_code) +
                                     " body: " + response);
        }
    }

    const std::string& getResponse() const {
        return response;
    }
};

#endif
