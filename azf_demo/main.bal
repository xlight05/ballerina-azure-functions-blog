//Hello world

// import ballerinax/azure_functions as af;

// service / on new af:HttpListener() {
//     resource function get greeting() returns json {
//         return {message: "Hello world"};
//     }
// }

//Dog Review 
import ballerinax/azure_functions as af;
import ballerina/http;
import ballerina/uuid;

configurable string visionApp = ?;
configurable string subscriptionKey = ?;
configurable string blobStoreName = ?;

service /reviews on new af:HttpListener() {
    resource function post upload(@http:Payload byte[]|error image, string name) returns @af:BlobOutput {path: "images/{Query.name}"} byte[]|error {
        return image;
    }
}

public type Entry record {
    string id;
    boolean isDog;
    string imageUrl;
    string description;
};

type ImageAnalyzeResponse record {
    Category[] categories;
    Description description;
    string requestId;
    Metadata metadata;
    string modelVersion;
};

type Description record {
    string[] tags;
    Caption[] captions;
};

type Caption record {
    string text;
    decimal confidence;
};

type Category record {
    string name;
    decimal score;
};

type Metadata record {
    int height;
    int width;
    string format;
};

@af:BlobTrigger {
    path: "images/{name}"
}
listener af:BlobListener blobListener = new af:BlobListener();

service "on-image" on blobListener {
    remote function onUpdated(byte[] image, @af:BindingName string name) returns @af:CosmosDBOutput {
        connectionStringSetting: "CosmosDBConnection",
        databaseName: "reviewdb",
        collectionName: "c1"
    } Entry|error {

        var [isDog, description] = check getImageInsights(image);

        return {
            id: uuid:createType1AsString(),
            imageUrl: "https://" + blobStoreName + ".blob.core.windows.net/images/" + name,
            isDog: isDog,
            description: description
        };
    }
}

function getImageInsights(byte[] image) returns [boolean, string]|error {
    final http:Client clientEndpoint = check new ("https://" + visionApp + ".cognitiveservices.azure.com/vision/v3.2/analyze", {
        timeout: 10,
        httpVersion: http:HTTP_1_1
    });

    http:Request req = new ();
    req.setBinaryPayload(image);
    req.addHeader("Ocp-Apim-Subscription-Key", subscriptionKey);
    ImageAnalyzeResponse resp = check clientEndpoint->post("/?visualFeatures=Categories,Description", req);

    string[] dogs = from string tag in resp.description.tags
        where tag.includes("dog")
        select tag;

    if (dogs.length() > 0) {
        Caption[] captions = resp.description.captions;
        string description = "";
        if (captions.length() > 0) {
            Caption caption = captions[0];
            description = caption.text;
        }
        return [true, description];
    }
    return [false, ""];
}

service /dashboard on ep {
    resource function get .(@af:CosmosDBInput {
                                connectionStringSetting: "CosmosDBConnection",
                                databaseName: "reviewdb",
                                collectionName: "c1",
                                sqlQuery: "SELECT * FROM Items"
                            } Entry[] entries) returns @af:HttpOutput Entry[]|error {
        return entries;
    }
}
