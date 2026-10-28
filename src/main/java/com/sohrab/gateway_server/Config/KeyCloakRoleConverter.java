package com.sohrab.gateway_server.Config;

import org.springframework.core.convert.converter.Converter;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Map;

public class KeyCloakRoleConverter implements Converter<Jwt, Collection<GrantedAuthority>> {


    @Override
    public Collection<GrantedAuthority> convert(Jwt source) {

        Collection<GrantedAuthority> authorities = new ArrayList<>();

        Map<String, Object> realm_access = source.getClaimAsMap("realm_access");
        if (realm_access != null && realm_access.containsKey("roles")) {
            List<String> realmRoles = (List<String>) realm_access.get("roles");
            realmRoles.forEach(role -> authorities.add(new SimpleGrantedAuthority("ROLE_" + role.toUpperCase())));
        }

        Map<String, Object> resource_access = source.getClaimAsMap("resource_access");
        if (resource_access != null) {
            resource_access.forEach((client, clientDetails) -> {
                Map<String, Object> clientRoles = (Map<String, Object>) clientDetails;
                if (clientRoles != null) {
                    if (clientRoles.containsKey("roles")) {
                        List<String> roles = (List<String>) clientRoles.get("roles");
                        roles.forEach(role -> authorities.add(new SimpleGrantedAuthority("ROLE_" + role.toUpperCase())));
                    }
                }
            });
        }
        return authorities;
    }
}
