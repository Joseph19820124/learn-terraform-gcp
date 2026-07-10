package com.example.caller;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;

import java.net.http.HttpClient;
import java.time.Duration;

// caller:公开的 Cloud Run 服务(allUsers 有 run.invoker)。/hello 会转身去调用
// callee —— callee 的 URL 由环境变量 CALLEE_URL 注入(Cloud Run 部署后生成的
// https://xxx.a.run.app 地址)。
//
// 和 day09/10 最大的不同:AWS 那两天鉴权/隔离完全在网络层(安全组、prefix
// list)，应用代码不用关心。Cloud Run 的 IAM 鉴权是"调用方主动出示凭证"的
// 模型 —— 每次请求前，caller 必须先向 GCP 的 metadata server 要一个
// Google 签发的 OIDC identity token(audience 设成 callee 的 URL)，再把它
// 塞进 Authorization: Bearer 头里。callee 收到请求后，Cloud Run 平台会在
// 流量到达容器之前校验这个 token 对应的调用方身份是否有 roles/run.invoker
// 权限 —— 校验本身容器代码完全不用写。
@SpringBootApplication
@RestController
public class CallerApplication {

    private static final String CALLEE_URL =
            System.getenv().getOrDefault("CALLEE_URL", "http://localhost:8080");

    private static final String METADATA_IDENTITY_URL =
            "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity";

    private final RestClient client;

    public CallerApplication() {
        JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory(
                HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build());
        factory.setReadTimeout(Duration.ofSeconds(3));
        this.client = RestClient.builder().requestFactory(factory).build();
    }

    public static void main(String[] args) {
        SpringApplication.run(CallerApplication.class, args);
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }

    @GetMapping("/hello")
    public String hello() {
        String idToken = fetchIdentityToken(CALLEE_URL);

        String body = client.get()
                .uri(CALLEE_URL + "/data")
                .header("Authorization", "Bearer " + idToken)
                .retrieve()
                .onStatus(HttpStatusCode::isError, (req, res) -> {})
                .body(String.class);
        return "Caller says hi! Called " + CALLEE_URL
                + "/data via Cloud Run IAM auth, got back: " + body;
    }

    // 向 GCP metadata server 要一个 audience 绑定到 callee URL 的 Google 签发
    // identity token。这是 Cloud Run 服务间调用的标准做法:token 只对这一个
    // audience 有效，callee 那边校验时会核对 aud 声明是不是自己的 URL。
    private String fetchIdentityToken(String audience) {
        return client.get()
                .uri(METADATA_IDENTITY_URL + "?audience=" + audience)
                .header("Metadata-Flavor", "Google")
                .retrieve()
                .body(String.class);
    }
}
