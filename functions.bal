import ballerina/log;
import ballerina/ftp;
import ballerinax/health.fhir.r4utils.ccdatofhir;
import ballerinax/health.fhir.r4;

function moveFileToErrorDirectory(string fileName, string fileContent) {
    ftp:Error? deletedFile = ftpClient->delete(path = incomingCcdaFileDir + fileName);
    if deletedFile is ftp:Error {
        log:printError("Error deleting file", deletedFile);
    }
    ftp:Error? failedFile = ftpClient->put(path = failedCcdaFileDir + fileName, content = fileContent);
    if failedFile is ftp:Error {
        log:printError("Error uploading file to error directory", failedFile);
    } else {
        log:printInfo("File moved to error directory successfully");
    }
}

function processCcdaFileContent(xml content) returns r4:Bundle|error? {

    r4:Bundle|r4:FHIRError ccdaToFhir = ccdatofhir:ccdaToFhir(content);
    if ccdaToFhir is r4:Bundle {
        log:printInfo("CCDA to FHIR conversion successful", convertedBundle = ccdaToFhir);
        return ccdaToFhir;
    } else {
        log:printError("Error converting CCDA to FHIR", ccdaToFhir);
        return error("Error converting CCDA to FHIR");
    }
}