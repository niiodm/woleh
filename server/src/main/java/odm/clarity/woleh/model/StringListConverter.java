package odm.clarity.woleh.model;

import java.util.Collections;
import java.util.List;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Persists {@code List<String>} as a compact JSON array string (e.g. {@code ["a","b"]}).
 * Used for {@link Plan#permissionsGranted}.  Not auto-applied; opt in with
 * {@code @Convert(converter = StringListConverter.class)}.
 */
@Converter
public class StringListConverter implements AttributeConverter<List<String>, String> {

	private static final ObjectMapper MAPPER = new ObjectMapper();

	@Override
	public String convertToDatabaseColumn(List<String> list) {
		if (list == null || list.isEmpty()) return "[]";
		try {
			return MAPPER.writeValueAsString(list);
		} catch (JsonProcessingException e) {
			throw new IllegalStateException("Could not serialize permissions list", e);
		}
	}

	@Override
	public List<String> convertToEntityAttribute(String json) {
		if (json == null || json.isBlank()) return Collections.emptyList();
		try {
			return MAPPER.readValue(json, new TypeReference<List<String>>() {});
		} catch (JsonProcessingException e) {
			throw new IllegalStateException("Could not deserialize permissions list: " + json, e);
		}
	}
}
