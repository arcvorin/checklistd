//
//  Sync.swift
//  Checklistd
//
//  Created by Arc Vorin on 2026-07-17.
//
import SwiftGitX
import Foundation
import Network
import KeychainSwift
nonisolated class OauthSyncEngine {
    let keychain = KeychainSwift()
    struct DeviceCodeResponse: Decodable {
        let device_code: String
        let user_code: String
        let verification_uri: String
        let expires_in: Int
        let interval: Int
    }

    struct AccessTokenResponse: Decodable {
        let accessToken: String?
        let tokenType: String?
        let scope: String?
        let refreshToken: String?
        let expiresIn: Int?
        let refreshTokenExpiresIn: Int?
        let error: String?
        let errorDescription: String?
        let errorUri: String?
        
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case scope
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case refreshTokenExpiresIn = "refresh_token_expires_in"
            case error
            case errorDescription = "error_description"
            case errorUri = "error_uri"
        }
    }
    
    let clientID = "Ov23li9jcAwYl63uZDR4"
    func getToken() -> String? {
        return keychain.get("token")
    }
    
    func requestDeviceCode() async throws -> DeviceCodeResponse {
        var request = URLRequest(
            url: URL(string: "https://github.com/login/device/code")!
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = "client_id=\(clientID)&scope=read:user"
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }
    
    func pollForAccessToken(
        clientID: String,
        deviceCode: String
    ) async throws -> AccessTokenResponse {
        while true {
            var request = URLRequest(
                url: URL(string: "https://github.com/login/oauth/access_token")!
            )
            request.httpMethod = "POST"
            request.setValue(
                "application/x-www-form-urlencoded",
                forHTTPHeaderField: "Content-Type"
            )
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let body =
                "client_id=\(clientID)" +
                "&device_code=\(deviceCode)" +
                "&grant_type=urn:ietf:params:oauth:grant-type:device_code"

            request.httpBody = body.data(using: .utf8)

            let (data, _) = try await URLSession.shared.data(for: request)
            print(String(data: data, encoding: .utf8))
            let response = try JSONDecoder().decode(
                AccessTokenResponse.self,
                from: data
            )

            if response.accessToken != nil {
                return response
            }
            try await Task.sleep(for: .seconds(1))
            switch response.error {
            case "authorization_pending":
                try await Task.sleep(for: .seconds(5))
            case "slow_down":
                try await Task.sleep(for: .seconds(10))
            default:
                throw NSError(
                    domain: "GitHubAuth",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: response.errorDescription ?? "Unknown auth error"]
                )
            }
        }
    }
    
    func sync() {
    }
    
    func prepare(deviceCode: String)  {
        if (getToken() != nil) {
            return 
        }
        Task.detached(operation: { [weak self] in
            guard let self = self else {
                return
            }
            do {
                let response = try await self.pollForAccessToken(clientID: clientID, deviceCode: deviceCode)
                 guard let token = response.accessToken else{
                    return
                }
                if keychain.set(token, forKey: "token") {
                    print("Saved token to keychain")
                } else {
                    print("Failed to save token to keychain: \(keychain.lastResultCode)")
                }
            } catch {
                print(error)
            }
        })
    }
}
