package com.example.callee;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

// callee:一个普通的 Cloud Run 服务 —— 不需要加入 mesh、不需要 --mesh
// 参数、代码和 day11 的 callee 完全一样。它只是被注册成了 mesh 的一个
// "目标"(通过 Serverless NEG + backend service + HTTPRoute)，自己完全不
// 知道调用方是通过 Envoy sidecar 转发过来的。IAM 层面仍然只允许 caller
// 的服务账号调用(roles/run.invoker)——mesh 解决的是"调用方怎么发现/怎么
// 附加凭证"，不是替代 IAM 授权本身。
@SpringBootApplication
@RestController
public class CalleeApplication {

    public static void main(String[] args) {
        SpringApplication.run(CalleeApplication.class, args);
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }

    @GetMapping("/data")
    public String data() {
        return "{\"from\":\"callee\",\"message\":\"Hello from the callee service — reached via Cloud Service Mesh (Envoy sidecar + Serverless NEG), no manual token code needed!\"}";
    }
}
