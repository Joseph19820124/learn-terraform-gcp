package com.example.caller;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

// caller:接入了 Cloud Service Mesh 的 Cloud Run 服务(部署时带 --mesh 参数，
// Cloud Run 平台自动给它注入一个 Envoy sidecar)。/hello 调用 callee 用的是
// mesh 内部的主机名(http://callee.day12.internal/data)，不是 callee 真实的
// Cloud Run URL —— 出站流量先被同一个 revision 里的 Envoy sidecar 拦截，
// Envoy 查询 mesh 控制面拿到路由规则，转发到 callee 对应的 Serverless NEG。
//
// 和 day11 最大的不同、也是这一天最核心的对比点:day11 里，应用代码必须
// 自己去 metadata server 要 identity token、自己拼 Authorization 头——
// 这是 Cloud Run"裸" IAM 鉴权模型下调用方的责任。这一天引入 mesh 之后，
// Envoy sidecar 会自动帮调用方签发并附加身份凭证，应用代码完全不用管认证，
// 又变回了 day09/10 那种"纯网络透明调用"的写法。换句话说:service mesh
// 换来的东西之一就是"把鉴权这件事从应用代码里搬回基础设施层"。
@SpringBootApplication
@RestController
public class CallerApplication {

    private static final String CALLEE_URL =
            System.getenv().getOrDefault("CALLEE_URL", "http://localhost:8080");

    private final HttpClient client = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(3))
            .build();

    public static void main(String[] args) {
        SpringApplication.run(CallerApplication.class, args);
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }

    @GetMapping("/hello")
    public String hello() throws Exception {
        HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(CALLEE_URL + "/data"))
                .timeout(Duration.ofSeconds(3))
                .GET()
                .build();
        HttpResponse<String> resp = client.send(req, HttpResponse.BodyHandlers.ofString());
        return "Caller says hi! Called " + CALLEE_URL
                + "/data via Cloud Service Mesh (Envoy sidecar handled auth), got back: " + resp.body();
    }
}
