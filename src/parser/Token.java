package parser;

public class Token {
    private TokenCode code;
    private String value;

    public Token(TokenCode code, String value) {
        this.code = code;
        this.value = value;
    }

    public TokenCode getCode() {
        return code;
    }

    public String getValue() {
        return value;
    }

    @Override
    public String toString() {
        return "Token{" + code + ", '" + value + "'}";
    }
}
